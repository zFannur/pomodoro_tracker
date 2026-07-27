/// Чистый кодек markdown-форматов хранилища. Без зависимостей от Flutter/IO.
library;

import '../domain/entities/pomo_session.dart';
import '../domain/entities/pomo_task.dart';
import '../domain/entities/sprint.dart';

// ---------------------------------------------------------------------------
// Даты и ISO-недели
// ---------------------------------------------------------------------------

String two(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String dateHuman(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

int isoWeekNumber(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  // Четверг той же недели однозначно определяет ISO-год и номер недели.
  final thursday = DateTime(d.year, d.month, d.day + (4 - d.weekday));
  final firstDay = DateTime(thursday.year);
  return (thursday.difference(firstDay).inDays ~/ 7) + 1;
}

int isoWeekYear(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return DateTime(d.year, d.month, d.day + (4 - d.weekday)).year;
}

/// Идентификатор спринта вида `2026-W29`.
String sprintId(DateTime date) =>
    '${isoWeekYear(date)}-W${two(isoWeekNumber(date))}';

const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$mм';
  return m == 0 ? '$hч' : '$hч $mм';
}

// ---------------------------------------------------------------------------
// Строка задачи плана: `- Описание #категория ⏱ 50м`
// ---------------------------------------------------------------------------

const _fallbackCategory = 'прочее';

final _planLineRe = RegExp(r'^\s*- (?!\[)(.+)$');
final _durationTailRe = RegExp(r'\s*⏱\s*(\d+)\s*м?\s*$');
final _categoryTailRe = RegExp(r'\s#([^\s#]+)\s*$');
final _dueTailRe = RegExp(r'\s*📅\s*(\d{4})-(\d{2})-(\d{2})\s*$');

PomoTask? parsePlanLine(String line, {int defaultDuration = 25}) {
  final m = _planLineRe.firstMatch(line);
  if (m == null) return null;
  var rest = m.group(1)!.trim();

  // Маркеры системы: 🐸 лягушка (префикс), ⭐ задача недели (суффикс).
  var frog = false;
  if (rest.startsWith('🐸')) {
    frog = true;
    rest = rest.substring('🐸'.length).trimLeft();
  }
  var week = false;
  if (rest.endsWith('⭐')) {
    week = true;
    rest = rest.substring(0, rest.length - '⭐'.length).trimRight();
  }

  DateTime? due;
  final dueMatch = _dueTailRe.firstMatch(rest);
  if (dueMatch != null) {
    due = DateTime(
      int.parse(dueMatch.group(1)!),
      int.parse(dueMatch.group(2)!),
      int.parse(dueMatch.group(3)!),
    );
    rest = rest.substring(0, dueMatch.start).trimRight();
  }

  var duration = defaultDuration;
  final dur = _durationTailRe.firstMatch(rest);
  if (dur != null) {
    duration = int.tryParse(dur.group(1)!) ?? defaultDuration;
    rest = rest.substring(0, dur.start).trimRight();
  }

  var category = _fallbackCategory;
  final cat = _categoryTailRe.firstMatch(rest);
  if (cat != null) {
    category = cat.group(1)!;
    rest = rest.substring(0, cat.start).trimRight();
  }

  if (rest.isEmpty) return null;
  return PomoTask(
    description: rest,
    category: category,
    durationMinutes: duration < 1 ? defaultDuration : duration,
    due: due,
    frog: frog,
    week: week,
  );
}

String planLine(PomoTask t) {
  final buf = StringBuffer('- ');
  if (t.frog) buf.write('🐸 ');
  buf.write('${t.description} #${t.category} ⏱ ${t.durationMinutes}м');
  final due = t.due;
  if (due != null) buf.write(' 📅 ${dateKey(due)}');
  if (t.week) buf.write(' ⭐');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Задачи.md
// ---------------------------------------------------------------------------

const todayHeading = 'Сегодня';
const plannerHeading = 'Планировщик';

TasksFile parseTasksFile(String content) {
  final todo = <PomoTask>[];
  final planner = <PomoTask>[];
  List<PomoTask>? current;
  for (final line in content.split('\n')) {
    final heading = RegExp(r'^##\s+(.+?)\s*$').firstMatch(line);
    if (heading != null) {
      current = switch (heading.group(1)) {
        todayHeading => todo,
        plannerHeading => planner,
        _ => null,
      };
      continue;
    }
    if (current == null) continue;
    final task = parsePlanLine(line);
    if (task != null) current.add(task);
  }
  return TasksFile(todo: todo, planner: planner);
}

String serializeTasksFile(TasksFile file) {
  final buf = StringBuffer('# Задачи\n')
    ..write('\n## $todayHeading\n')
    ..writeAll(file.todo.map((t) => '${planLine(t)}\n'))
    ..write('\n## $plannerHeading\n')
    ..writeAll(file.planner.map((t) => '${planLine(t)}\n'));
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Frontmatter
// ---------------------------------------------------------------------------

Map<String, String> parseFrontmatter(String content) {
  final result = <String, String>{};
  final lines = content.split('\n');
  // Пропускаем пустые строки и HTML-комментарии до frontmatter: зеркала
  // пишутся с шапкой «<!-- Зеркало… -->» первой строкой, и требование «--- на
  // первой строке» означало, что на РЕАЛЬНЫХ файлах приложения frontmatter не
  // читался никогда — спринты восстанавливались с нулевой целью и пустой вехой.
  var start = 0;
  while (start < lines.length) {
    final line = lines[start].trim();
    if (line.isEmpty || line.startsWith('<!--')) {
      start++;
      continue;
    }
    break;
  }
  if (start >= lines.length || lines[start].trim() != '---') return result;
  for (final line in lines.skip(start + 1)) {
    if (line.trim() == '---') break;
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
  }
  return result;
}

// ---------------------------------------------------------------------------
// Журнал дня («Сделано»): Журнал/YYYY-MM/YYYY-MM-DD.md
// ---------------------------------------------------------------------------

String _cell(String s) => s.replaceAll('|', '∣');

/// Обратная замена при парсе — иначе `|` в тексте необратимо превращался в ∣.
String _uncell(String s) => s.replaceAll('∣', '|');

const _manualMark = 'вручную';
const _timerMark = 'таймер';

String serializeDayLog(DayLog log) {
  final buf = StringBuffer()
    ..write('---\n')
    ..write('дата: ${dateKey(log.date)}\n')
    ..write('помидоры: ${log.count}\n')
    ..write('минуты: ${log.minutes}\n')
    ..write('простой: ${log.delayMinutes}\n')
    ..write('прерывания: ${log.interruptions}\n')
    ..write('фокус: ${log.focus}%\n')
    ..write('цель: ${log.goal}\n')
    ..write('---\n\n')
    ..write(
      '# ${dateHuman(log.date)} · ${log.count} 🍅 · '
      '${formatMinutes(log.minutes)} · фокус ${log.focus}%\n\n',
    )
    ..write(
      '| Начало | Мин | Простой | Прерывания | Категория | Задача | Как |\n',
    )
    ..write(
      '| ------ | --- | ------- | ---------- | --------- | ------ | --- |\n',
    );
  for (final s in log.sessions) {
    buf.write(
      '| ${two(s.start.hour)}:${two(s.start.minute)} | ${s.minutes} '
      '| ${s.delayMinutes} | ${s.interruptions} '
      '| ${_cell(s.category)} | ${s.frog ? '🐸 ' : ''}${_cell(s.task)} '
      '| ${s.manual ? _manualMark : _timerMark} |\n',
    );
  }
  if (log.notes.isNotEmpty) {
    buf.write('\n## Заметки\n');
    for (final note in log.notes) {
      buf.write('- $note\n');
    }
  }
  return buf.toString();
}

final _rowRe = RegExp(
  r'^\|\s*(\d{1,2}):(\d{2})\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|\s*$',
);

DayLog parseDayLog(String content, DateTime date, int fallbackGoal) {
  final fm = parseFrontmatter(content);
  final goal = int.tryParse(fm['цель'] ?? '') ?? fallbackGoal;
  final sessions = <PomoSession>[];
  final notes = <String>[];
  // Счётчик записей на одну и ту же минуту — разводит их id.
  final sameMinute = <String, int>{};
  var inNotes = false;
  for (final line in content.split('\n')) {
    if (line.startsWith('## ')) {
      inNotes = line.startsWith('## Заметки');
      continue;
    }
    if (inNotes) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ')) notes.add(trimmed.substring(2));
      continue;
    }
    final m = _rowRe.firstMatch(line.trim());
    if (m == null) continue;
    final hour = int.parse(m.group(1)!);
    // 🐸-префикс в задаче = помидор над лягушкой дня.
    var task = _uncell(m.group(7)!.trim());
    final frog = task.startsWith('🐸');
    if (frog) task = task.replaceFirst('🐸', '').trim();
    // id детерминированный, а не случайный: markdown его не хранит, а два
    // устройства мигрируют одну и ту же историю независимо друг от друга —
    // при случайных id первое же слияние удвоило бы весь журнал.
    final slot = '${two(hour)}${m.group(2)!}';
    final n = sameMinute[slot] = (sameMinute[slot] ?? -1) + 1;
    // День 05:00–05:00: часы 0–4 принадлежат следующей календарной дате.
    sessions.add(
      PomoSession(
        id: 'm${dateKey(date)}-$slot-$n',
        start: DateTime(
          date.year,
          date.month,
          hour < 5 ? date.day + 1 : date.day,
          hour,
          int.parse(m.group(2)!),
        ),
        minutes: int.parse(m.group(3)!),
        delayMinutes: int.parse(m.group(4)!),
        interruptions: int.parse(m.group(5)!),
        category: _uncell(m.group(6)!.trim()),
        task: task,
        manual: m.group(8)!.trim() == _manualMark,
        frog: frog,
      ),
    );
  }
  return DayLog(date: date, goal: goal, sessions: sessions, notes: notes);
}

// ---------------------------------------------------------------------------
// Спринт: Спринты/YYYY-Wnn.md
// ---------------------------------------------------------------------------

String serializeSprint(
  Sprint sprint,
  List<DayLog> fact, {
  List<PomoTask> weekTasks = const [],
}) {
  final total = fact.fold(0, (sum, d) => sum + d.count);
  final minutes = fact.fold(0, (sum, d) => sum + d.minutes);
  final percent = sprint.goal > 0 ? (total * 100 ~/ sprint.goal) : 0;
  final buf = StringBuffer()
    ..write('---\n')
    ..write('спринт: ${sprint.id}\n')
    ..write('начало: ${dateKey(sprint.start)}\n')
    ..write('конец: ${dateKey(sprint.end)}\n')
    ..write('цель: ${sprint.goal}\n')
    ..write('веха: ${sprint.milestone}\n')
    ..write('факт: $total\n')
    ..write('минуты: $minutes\n')
    ..write('---\n\n')
    ..write(
      '# Спринт ${sprint.id} '
      '(${two(sprint.start.day)}.${two(sprint.start.month)} – '
      '${two(sprint.end.day)}.${two(sprint.end.month)})\n\n',
    );
  if (sprint.milestone.isNotEmpty) {
    buf.write('**Веха:** ${sprint.milestone}\n\n');
  }
  buf.write(
    '**Цель:** ${sprint.goal} 🍅 · **Факт:** $total 🍅 · **$percent%** '
    '· ${formatMinutes(minutes)}\n',
  );
  // Снапшот ⭐-задач недели (живут в Задачи.md, здесь — для наглядности).
  buf.write('\n## Задачи недели\n');
  for (final t in weekTasks) {
    buf.write('${planLine(t)}\n');
  }
  buf.write('\n## Сделано за неделю\n');
  for (final line in sprint.doneWeek) {
    buf.write('- $line\n');
  }
  buf
    ..write('\n## По дням\n')
    ..write('| День | Дата | 🍅 | Мин |\n')
    ..write('| ---- | ---- | -- | --- |\n');
  for (final day in fact) {
    buf.write(
      '| ${weekdayShort[day.date.weekday - 1]} | ${dateHuman(day.date)} '
      '| ${day.count} | ${day.minutes} |\n',
    );
  }
  return buf.toString();
}

/// Восстанавливает редактируемую часть спринта (цель, веху, сделанное).
Sprint parseSprint(
  String content,
  String id,
  DateTime start,
  int fallbackGoal,
) {
  final fm = parseFrontmatter(content);
  final goal = int.tryParse(fm['цель'] ?? '') ?? fallbackGoal;
  final doneWeek = <String>[];
  var inDone = false;
  for (final line in content.split('\n')) {
    if (line.startsWith('## ')) {
      inDone = line.startsWith('## Сделано за неделю');
      continue;
    }
    if (!inDone) continue;
    final trimmed = line.trim();
    if (trimmed.startsWith('- ')) doneWeek.add(trimmed.substring(2));
  }
  return Sprint(
    id: id,
    start: start,
    goal: goal,
    milestone: fm['веха'] ?? '',
    doneWeek: doneWeek,
  );
}

SprintSummary? parseSprintSummary(String content) {
  final fm = parseFrontmatter(content);
  final id = fm['спринт'];
  if (id == null || id.isEmpty) return null;
  return SprintSummary(
    id: id,
    goal: int.tryParse(fm['цель'] ?? '') ?? 0,
    fact: int.tryParse(fm['факт'] ?? '') ?? 0,
    minutes: int.tryParse(fm['минуты'] ?? '') ?? 0,
  );
}
