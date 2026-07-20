import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/failure.dart';
import '../domain/entities/pomo_session.dart';
import '../domain/entities/pomo_task.dart';
import '../domain/entities/sprint.dart';
import '../domain/repositories.dart';
import 'markdown_codec.dart';
import 'vault_repositories.dart';

/// Стабильный id: время + случайный хвост. Сортируемый по времени создания,
/// генерится оффлайн, коллизии практически исключены.
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = Random().nextInt(0x7FFFFFFF).toRadixString(36);
  return '$time-$rand';
}

/// Всё состояние приложения одним документом — задачи, журнал, спринты и
/// надгробия удалённых записей.
///
/// Один файл, а не три, по двум причинам. Во-первых, закрытие задачи и запись
/// помидора — одна операция в коде: при раздельных файлах второе устройство
/// могло бы увидеть списанные минуты без помидора в журнале. Во-вторых, синк
/// остаётся ровно тем же, что уже отлажен на задачах: один файл, одна ревизия.
///
/// Истина — этот JSON. Markdown в валте (Задачи/Журнал/Спринты) пишется как
/// одностороннее зеркало для чтения в Obsidian и обратно не читается.
class JsonDataRepository
    implements TaskRepository, JournalRepository, SprintRepository {
  JsonDataRepository(
    this._store, {
    required this.mirrorEnabled,
    Future<String> Function()? dirProvider,
  }) : _dirProvider =
           dirProvider ??
           (() async => (await getApplicationSupportDirectory()).path);

  final VaultStore _store;
  final bool Function() mirrorEnabled;
  final Future<String> Function() _dirProvider;

  /// Локальные данные изменились — синку пора запланировать отправку.
  void Function()? onSaved;

  File? _file;
  _Doc? _doc;

  /// Надгробия старше этого срока вычищаются: удаление к этому моменту
  /// доехало до всех устройств, а держать список вечно незачем.
  static const _graveTtl = Duration(days: 90);

  static const _mirrorNote =
      '<!-- Зеркало Помодоро Трекера: правки здесь не читаются. -->\n';

  Future<File> jsonFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final file = File('${await _dirProvider()}${Platform.pathSeparator}data.json');
    _file = file;
    return file;
  }

  // -- документ ---------------------------------------------------------------

  Future<_Doc> _load() async {
    final cached = _doc;
    if (cached != null) return cached;
    final file = await jsonFile();
    if (await file.exists()) {
      return _doc = _Doc.decode(await file.readAsString());
    }
    return _doc = await _migrate();
  }

  /// Первый запуск новой версии: собрать документ из того, что уже есть —
  /// tasks.json синка и markdown валта. Файлы-источники не удаляем.
  Future<_Doc> _migrate() async {
    final doc = _Doc.empty();
    final dir = await _dirProvider();
    final legacy = File('$dir${Platform.pathSeparator}tasks.json');
    if (await legacy.exists()) {
      final json = jsonDecode(await legacy.readAsString());
      if (json is Map<String, dynamic>) {
        doc.todo.addAll(_tasks(json['todo']));
        doc.planner.addAll(_tasks(json['planner']));
      }
    } else {
      // Ещё более старая схема: задачи лежали только в валте.
      final content = await _store.read(_store.tasksFile());
      if (content != null) {
        final parsed = parseTasksFile(content);
        doc.todo.addAll(parsed.todo);
        doc.planner.addAll(parsed.planner);
      }
    }
    await _migrateJournal(doc);
    await _migrateSprints(doc);
    // id задачам могли не выдать в древних версиях.
    for (final list in [doc.todo, doc.planner]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == null) list[i] = list[i].copyWith(id: newId());
      }
    }
    await _write(doc);
    return doc;
  }

  Future<void> _migrateJournal(_Doc doc) async {
    final root = Directory(
      '${_store.root}${Platform.pathSeparator}${VaultStore.journalDirName}',
    );
    if (!await root.exists()) return;
    await for (final entry in root.list(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final name = entry.uri.pathSegments.last.replaceAll('.md', '');
      final date = DateTime.tryParse(name);
      if (date == null) continue;
      // id сессий детерминированные (см. parseDayLog) — два устройства,
      // мигрировавшие одну историю независимо, получат одинаковые.
      doc.days[dateKey(date)] = parseDayLog(await entry.readAsString(), date, 0);
    }
  }

  Future<void> _migrateSprints(_Doc doc) async {
    final dir = _store.sprintsDir();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final id = entry.uri.pathSegments.last.replaceAll('.md', '');
      final monday = _mondayOfSprint(id);
      if (monday == null) continue;
      doc.sprints[id] = parseSprint(await entry.readAsString(), id, monday, 0);
    }
  }

  /// Понедельник недели по её id вида `2026-W29`.
  static DateTime? _mondayOfSprint(String id) {
    final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(id);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final week = int.parse(m.group(2)!);
    // 4 января всегда в первой ISO-неделе года.
    final jan4 = DateTime(year, 1, 4);
    final firstMonday = mondayOf(jan4);
    return DateTime(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day + (week - 1) * 7,
    );
  }

  /// Записать документ: атомарно на диск, обновить надгробия, дёрнуть синк,
  /// затем обновить зеркала. Порядок важен — синк узнаёт о правке сразу,
  /// зеркало может отставать.
  Future<void> _write(_Doc doc, {Set<String>? before}) async {
    if (before != null) _updateGraves(doc, before);
    final file = await jsonFile();
    await file.parent.create(recursive: true);
    // Своё имя .tmp: у синка своё (.sync.tmp) — на общем уже ловили склейку
    // контента и битый JSON.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(doc.encode(), flush: true);
    await tmp.rename(file.path);
    _doc = doc;
    onSaved?.call();
  }

  /// Надгробия ставятся диффом при записи, а не в кубитах: так покрыты разом
  /// все пути удаления (минус в ноль, «очистить список», удаление записи
  /// журнала, слияние задач), и ни один из них не нужно править отдельно.
  void _updateGraves(_Doc doc, Set<String> before) {
    final now = doc.ids();
    final stamp = DateTime.now().toUtc().toIso8601String();
    for (final id in before.difference(now)) {
      doc.graves[id] = stamp;
    }
    // Запись вернулась (восстановление из корзины) — надгробие снимаем.
    // Только при локальной правке: при слиянии это сломало бы delete-wins.
    doc.graves.removeWhere((id, _) => now.contains(id));
    final deadline = DateTime.now().toUtc().subtract(_graveTtl);
    doc.graves.removeWhere((_, at) {
      final t = DateTime.tryParse(at);
      return t != null && t.isBefore(deadline);
    });
  }

  /// Синк принёс удалённую версию — принять её как есть и перечитать.
  Future<void> applyRemote(String content) async {
    final doc = _Doc.decode(content);
    final file = await jsonFile();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(doc.encode(), flush: true);
    await tmp.rename(file.path);
    _doc = doc;
    // onSaved не зовём: правка пришла снаружи, отправлять её обратно незачем.
    await _mirrorAll(doc);
  }

  // -- задачи -----------------------------------------------------------------

  @override
  Future<Either<Failure, TasksFile>> load() => _guard(() async {
    final doc = await _load();
    return TasksFile(todo: [...doc.todo], planner: [...doc.planner]);
  });

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile file) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    doc.todo
      ..clear()
      ..addAll(_withIds(file.todo));
    doc.planner
      ..clear()
      ..addAll(_withIds(file.planner));
    await _write(doc, before: before);
    await _mirrorTasks(doc);
    return unit;
  });

  /// Выдать id новым задачам и развести дубликаты: после «Разбить» копия
  /// делит id с оригиналом.
  List<PomoTask> _withIds(List<PomoTask> list) {
    final seen = <String>{};
    return [
      for (final t in list)
        if (t.id != null && seen.add(t.id!)) t else _fresh(t, seen),
    ];
  }

  PomoTask _fresh(PomoTask t, Set<String> seen) {
    final id = newId();
    seen.add(id);
    return t.copyWith(id: id);
  }

  List<PomoTask> _tasks(Object? raw) => [
    if (raw is List)
      for (final e in raw.whereType<Map<String, dynamic>>()) _taskFrom(e),
  ];

  PomoTask _taskFrom(Map<String, dynamic> j) {
    final minutes = (j['min'] as num?)?.toInt() ?? 1;
    final due = j['due'];
    return PomoTask(
      id: j['id'] as String?,
      description: j['desc'] as String? ?? '',
      category: j['cat'] as String? ?? 'прочее',
      durationMinutes: minutes < 1 ? 1 : minutes,
      due: due is String ? DateTime.tryParse(due) : null,
      frog: j['frog'] == true,
      week: j['week'] == true,
    );
  }

  // -- журнал -----------------------------------------------------------------

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int dailyGoal) =>
      _guard(() async {
        final doc = await _load();
        return _dayOf(doc, date, dailyGoal);
      });

  DayLog _dayOf(_Doc doc, DateTime date, int dailyGoal) {
    final normalized = DateTime(date.year, date.month, date.day);
    final existing = doc.days[dateKey(normalized)];
    if (existing == null) {
      return DayLog(date: normalized, goal: dailyGoal, sessions: const []);
    }
    // Цель 0 у мигрированных дней — подставляем текущую настройку.
    return existing.goal == 0 ? existing.copyWith(goal: dailyGoal) : existing;
  }

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    doc.days[dateKey(log.date)] = log;
    await _write(doc, before: before);
    await _mirrorDay(log);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> addSession(PomoSession session, int dailyGoal) =>
      _guard(() async {
        final doc = await _load();
        final before = doc.ids();
        // День 05:00–05:00: помидор в 00:30 идёт во вчерашний день.
        final log = _dayOf(doc, logicalDate(session.start), dailyGoal);
        // copyWith — иначе потеряются заметки «на чём встал».
        final updated = log.copyWith(sessions: [...log.sessions, session]);
        doc.days[dateKey(log.date)] = updated;
        await _write(doc, before: before);
        await _mirrorDay(updated);
        return unit;
      });

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int dailyGoal,
  ) => _guard(() async {
    final doc = await _load();
    final result = <DayLog>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    // Пустые дни синтезируем: в JSON их нет, а на непрерывный ряд дат
    // завязаны серия дней в статистике и темп спринта.
    while (!cursor.isAfter(last)) {
      result.add(_dayOf(doc, cursor, dailyGoal));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return result;
  });

  // -- спринты ----------------------------------------------------------------

  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int defaultGoal) =>
      _guard(() async {
        final doc = await _load();
        final id = sprintId(now);
        final existing = doc.sprints[id];
        if (existing == null) {
          return Sprint(id: id, start: mondayOf(now), goal: defaultGoal);
        }
        return existing.goal == 0
            ? existing.copyWith(goal: defaultGoal)
            : existing;
      });

  @override
  Future<Either<Failure, Unit>> saveSprint(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks = const [],
  }) => _guard(() async {
    final doc = await _load();
    final existing = doc.sprints[sprint.id];
    // Факт в документе не хранится — он производный от журнала. Поэтому
    // сравниваем только редактируемые поля и выходим ДО записи и до onSaved:
    // иначе каждый помидор дёргал бы отправку в Drive.
    if (existing != null &&
        existing.goal == sprint.goal &&
        existing.milestone == sprint.milestone &&
        _sameList(existing.doneWeek, sprint.doneWeek)) {
      await _mirrorSprint(sprint, fact, weekTasks);
      return unit;
    }
    doc.sprints[sprint.id] = sprint;
    await _write(doc);
    await _mirrorSprint(sprint, fact, weekTasks);
    return unit;
  });

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<Either<Failure, List<SprintSummary>>> history() => _guard(() async {
    final doc = await _load();
    final summaries = <SprintSummary>[];
    for (final entry in doc.sprints.entries) {
      final monday = _mondayOfSprint(entry.key);
      if (monday == null) continue;
      // Факт считаем из журнала — отдельно он нигде не хранится.
      var fact = 0;
      var minutes = 0;
      for (var i = 0; i < 7; i++) {
        final day = doc.days[dateKey(
          DateTime(monday.year, monday.month, monday.day + i),
        )];
        if (day == null) continue;
        fact += day.count;
        minutes += day.minutes;
      }
      summaries.add(
        SprintSummary(
          id: entry.key,
          goal: entry.value.goal,
          fact: fact,
          minutes: minutes,
        ),
      );
    }
    summaries.sort((a, b) => b.id.compareTo(a.id));
    return summaries;
  });

  // -- зеркала в валт ---------------------------------------------------------

  /// Валт недоступен — молча пропускаем: данные от него не зависят.
  Future<void> _mirror(File file, String content) async {
    if (!mirrorEnabled()) return;
    try {
      // Без изменений не переписываем — меньше churn для Obsidian и Drive.
      if (await _store.read(file) == content) return;
      await _store.write(file, content);
    } on FileSystemException {
      // Намеренно молча.
    }
  }

  Future<void> _mirrorTasks(_Doc doc) => _mirror(
    _store.tasksFile(),
    _mirrorNote +
        serializeTasksFile(TasksFile(todo: doc.todo, planner: doc.planner)),
  );

  Future<void> _mirrorDay(DayLog log) =>
      _mirror(_store.journalFile(log.date), _mirrorNote + serializeDayLog(log));

  Future<void> _mirrorSprint(
    Sprint sprint,
    List<DayLog> fact,
    List<PomoTask> weekTasks,
  ) => _mirror(
    _store.sprintFile(sprint.id),
    _mirrorNote + serializeSprint(sprint, fact, weekTasks: weekTasks),
  );

  /// После прилёта удалённой версии — переписать зеркала целиком.
  Future<void> _mirrorAll(_Doc doc) async {
    await _mirrorTasks(doc);
    for (final log in doc.days.values) {
      await _mirrorDay(log);
    }
  }

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Either.right(await body());
    } on FileSystemException catch (e) {
      return Either.left(
        StorageFailure('Файловая ошибка: ${e.message} ${e.path ?? ''}'),
      );
    } on FormatException catch (e) {
      return Either.left(ParseFailure('Ошибка разбора: ${e.message}'));
    }
  }
}

/// Документ в памяти. Кодек живёт рядом с репозиторием: формат читает и
/// пишет только он, наружу отдаются доменные объекты.
class _Doc {
  _Doc({
    required this.todo,
    required this.planner,
    required this.days,
    required this.sprints,
    required this.graves,
    required this.rollover,
  });

  factory _Doc.empty() => _Doc(
    todo: [],
    planner: [],
    days: {},
    sprints: {},
    graves: {},
    rollover: {},
  );

  factory _Doc.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return _Doc.empty();
    final doc = _Doc.empty();
    doc.todo.addAll(_taskList(json['todo']));
    doc.planner.addAll(_taskList(json['planner']));
    final days = json['days'];
    if (days is Map<String, dynamic>) {
      for (final e in days.entries) {
        final date = DateTime.tryParse(e.key);
        if (date == null || e.value is! Map<String, dynamic>) continue;
        doc.days[e.key] = _dayFrom(date, e.value as Map<String, dynamic>);
      }
    }
    final sprints = json['sprints'];
    if (sprints is Map<String, dynamic>) {
      for (final e in sprints.entries) {
        final monday = JsonDataRepository._mondayOfSprint(e.key);
        if (monday == null || e.value is! Map<String, dynamic>) continue;
        final s = e.value as Map<String, dynamic>;
        doc.sprints[e.key] = Sprint(
          id: e.key,
          start: monday,
          goal: (s['goal'] as num?)?.toInt() ?? 0,
          milestone: s['milestone'] as String? ?? '',
          doneWeek: [
            if (s['done'] is List) ...(s['done'] as List).whereType<String>(),
          ],
        );
      }
    }
    final graves = json['graves'];
    if (graves is Map<String, dynamic>) {
      for (final e in graves.entries) {
        if (e.value is String) doc.graves[e.key] = e.value as String;
      }
    }
    final rollover = json['rollover'];
    if (rollover is Map<String, dynamic>) {
      for (final e in rollover.entries) {
        if (e.value is String) doc.rollover[e.key] = e.value as String;
      }
    }
    return doc;
  }

  final List<PomoTask> todo;
  final List<PomoTask> planner;
  final Map<String, DayLog> days;
  final Map<String, Sprint> sprints;
  final Map<String, String> graves;
  final Map<String, String> rollover;

  /// Все живые id — база для диффа надгробий.
  Set<String> ids() => {
    for (final t in todo)
      if (t.id != null) t.id!,
    for (final t in planner)
      if (t.id != null) t.id!,
    for (final d in days.values)
      for (final s in d.sessions) s.id,
  };

  String encode() => jsonEncode({
    'schema': 2,
    'todo': [for (final t in todo) _taskJson(t)],
    'planner': [for (final t in planner) _taskJson(t)],
    'days': {
      for (final e in days.entries)
        e.key: {
          'goal': e.value.goal,
          's': [for (final s in e.value.sessions) _sessionJson(s)],
          if (e.value.notes.isNotEmpty) 'n': e.value.notes,
        },
    },
    'sprints': {
      for (final e in sprints.entries)
        e.key: {
          'goal': e.value.goal,
          if (e.value.milestone.isNotEmpty) 'milestone': e.value.milestone,
          if (e.value.doneWeek.isNotEmpty) 'done': e.value.doneWeek,
        },
    },
    'graves': graves,
    if (rollover.isNotEmpty) 'rollover': rollover,
  });

  static List<PomoTask> _taskList(Object? raw) => [
    if (raw is List)
      for (final e in raw.whereType<Map<String, dynamic>>())
        PomoTask(
          id: e['id'] as String?,
          description: e['desc'] as String? ?? '',
          category: e['cat'] as String? ?? 'прочее',
          durationMinutes: ((e['min'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
          due: e['due'] is String ? DateTime.tryParse(e['due'] as String) : null,
          frog: e['frog'] == true,
          week: e['week'] == true,
        ),
  ];

  static Map<String, dynamic> _taskJson(PomoTask t) => {
    'id': t.id,
    'desc': t.description,
    'cat': t.category,
    'min': t.durationMinutes,
    if (t.due != null) 'due': dateKey(t.due!),
    if (t.frog) 'frog': true,
    if (t.week) 'week': true,
  };

  static DayLog _dayFrom(DateTime date, Map<String, dynamic> json) {
    final raw = json['s'];
    return DayLog(
      date: date,
      goal: (json['goal'] as num?)?.toInt() ?? 0,
      sessions: [
        if (raw is List)
          for (final e in raw.whereType<Map<String, dynamic>>())
            _sessionFrom(date, e),
      ],
      notes: [
        if (json['n'] is List) ...(json['n'] as List).whereType<String>(),
      ],
    );
  }

  /// Время хранится как `HH:mm`, дата берётся из ключа дня — ровно та же
  /// информация, что и в markdown, поэтому поведение не меняется.
  static PomoSession _sessionFrom(DateTime date, Map<String, dynamic> j) {
    final parts = '${j['t']}'.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return PomoSession(
      id: j['id'] as String? ?? newId(),
      // Часы 0–4 принадлежат следующей календарной дате: день с 05:00.
      start: DateTime(
        date.year,
        date.month,
        hour < 5 ? date.day + 1 : date.day,
        hour,
        minute,
      ),
      minutes: (j['m'] as num?)?.toInt() ?? 1,
      category: j['c'] as String? ?? '',
      task: j['d'] as String? ?? '',
      delayMinutes: (j['dl'] as num?)?.toInt() ?? 0,
      interruptions: (j['in'] as num?)?.toInt() ?? 0,
      manual: j['man'] == true,
      frog: j['frog'] == true,
    );
  }

  static Map<String, dynamic> _sessionJson(PomoSession s) => {
    'id': s.id,
    't': '${two(s.start.hour)}:${two(s.start.minute)}',
    'm': s.minutes,
    'c': s.category,
    'd': s.task,
    if (s.delayMinutes != 0) 'dl': s.delayMinutes,
    if (s.interruptions != 0) 'in': s.interruptions,
    if (s.manual) 'man': true,
    if (s.frog) 'frog': true,
  };
}
