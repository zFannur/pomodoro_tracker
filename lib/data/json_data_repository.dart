import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/failure.dart';
import '../domain/entities/direction.dart';
import '../domain/entities/episode.dart';
import '../domain/entities/experiment.dart';
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
    implements
        TaskRepository,
        JournalRepository,
        SprintRepository,
        InsightRepository,
        DirectionRepository {
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

  /// Очередь операций. `_guard`, `applyRemote` и миграция ходят в ОДИН файл, и
  /// раньше — через один и тот же `.tmp`: два вызова перекрывались на open с
  /// усечением, и на диск ложился битый JSON, а второй rename падал.
  Future<void> _io = Future.value();
  int _tmpSeq = 0;

  Future<T> _serial<T>(Future<T> Function() body) {
    final next = _io.then((_) => body());
    _io = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Что репозиторий в последний раз отдал наружу. Нужно, чтобы отличить
  /// «пользователь удалил» от «приехало синком, пока вызывающий держал старый
  /// снимок»: хоронить (и выбрасывать) можно только первое. Без этого правка
  /// в окне между applyRemote и перечитыванием стейта ставила надгробия на
  /// записи другого устройства — и delete-wins убивал их у всех навсегда.
  Set<String> _servedTasks = const {};
  final Map<String, Set<String>> _servedDays = {};
  Set<String> _servedCourse = const {};

  Future<File> jsonFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final file = File(
      '${await _dirProvider()}${Platform.pathSeparator}data.json',
    );
    _file = file;
    return file;
  }

  // -- документ ---------------------------------------------------------------

  Future<_Doc> _load() async {
    final cached = _doc;
    if (cached != null) return cached;
    final file = await jsonFile();
    if (await file.exists()) {
      final doc = _Doc.decode(await file.readAsString());
      _doc = doc;
      // Починку сразу на диск: иначе битый документ так и уезжал бы в Drive
      // при каждом пуше — на диске-то он не менялся.
      if (_dedupeBuckets(doc)) await _write(doc);
      return doc;
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
        // id детерминированные (как у сессий журнала): в зеркале их нет, а со
        // случайными два устройства, мигрировавшие один и тот же файл,
        // получали разные id — и после синка каждая задача удваивалась.
        for (var i = 0; i < parsed.todo.length; i++) {
          doc.todo.add(parsed.todo[i].copyWith(id: 'md-t$i'));
        }
        for (var i = 0; i < parsed.planner.length; i++) {
          doc.planner.add(parsed.planner[i].copyWith(id: 'md-p$i'));
        }
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
      doc.days[dateKey(date)] = parseDayLog(
        await entry.readAsString(),
        date,
        0,
      );
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

  static DateTime? _mondayOfSprint(String id) => mondayOfSprintId(id);

  /// Записать документ: атомарно на диск, обновить надгробия, дёрнуть синк,
  /// затем обновить зеркала. Порядок важен — синк узнаёт о правке сразу,
  /// зеркало может отставать.
  Future<void> _write(_Doc doc, {Set<String>? before}) async {
    if (before != null) _updateGraves(doc, before);
    await _dump(doc);
    onSaved?.call();
  }

  /// Атомарная запись документа. Имя временного файла уникально на вызов:
  /// общий `.tmp` склеивал содержимое двух параллельных писателей.
  Future<void> _dump(_Doc doc) async {
    final file = await jsonFile();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.${_tmpSeq++}.tmp');
    await tmp.writeAsString(doc.encode(), flush: true);
    await tmp.rename(file.path);
    _doc = doc;
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

  /// Отметки о смене дня и недели. Живут в документе, а не в локальных
  /// настройках: иначе второе устройство, открытое позже, повторно сбрасывало
  /// 🐸/⭐ — стирая флаги, только что расставленные на первом.
  Future<Either<Failure, ({String? day, String? week})>> rollover() =>
      _guard(() async {
        final doc = await _load();
        return (day: doc.rollover['day'], week: doc.rollover['week']);
      });

  /// Отметка о показанном месячном разборе (ключ 'month', напр. '2026-09').
  Future<Either<Failure, String?>> monthRollover() =>
      _guard(() async => (await _load()).rollover['month']);

  Future<Either<Failure, Unit>> markRollover({
    String? day,
    String? week,
    String? month,
  }) => _guard(() async {
    final doc = await _load();
    if (day != null) doc.rollover['day'] = day;
    if (week != null) doc.rollover['week'] = week;
    if (month != null) doc.rollover['month'] = month;
    await _write(doc);
    return unit;
  });

  /// Снимок таймера пишется ТОЛЬКО на переходах (старт/пауза/стоп/смена фазы):
  /// периодические сохранения раз в 15 секунд идут в локальный
  /// timer_state.json, иначе каждый идущий помидор давал бы четыре аплоада
  /// в Drive в минуту. Для чужого устройства (phaseEnd + total) достаточно,
  /// чтобы досчитать остаток по настенным часам.
  Future<Either<Failure, Unit>> saveTimer(Map<String, dynamic>? snap) =>
      _guard(() async {
        final doc = await _load();
        doc.timer = snap;
        await _write(doc);
        return unit;
      });

  Future<Either<Failure, Map<String, dynamic>?>> loadTimer() =>
      _guard(() async => (await _load()).timer);

  /// Синк принёс удалённую версию — принять её как есть и перечитать.
  Future<void> applyRemote(String content) async {
    final doc = _Doc.decode(content);
    _dedupeBuckets(doc);
    // onSaved не зовём: правка пришла снаружи, отправлять её обратно незачем.
    await _serial(() => _dump(doc));
    // Зеркала — вне критического пути. На длинной истории это файловая
    // операция на КАЖДЫЙ день, и всё это время кубиты держали бы доsync-снимок:
    // именно эта часть окна, а не сеть, была самой длинной.
    unawaited(_mirrorAll(doc));
  }

  // -- задачи -----------------------------------------------------------------

  @override
  Future<Either<Failure, TasksFile>> load() => _guard(() async {
    final doc = await _load();
    _servedTasks = {
      for (final t in [...doc.todo, ...doc.planner])
        if (t.id != null) t.id!,
    };
    return TasksFile(todo: [...doc.todo], planner: [...doc.planner]);
  });

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile file) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    final todo = _withIds(file.todo);
    final planner = _withIds(file.planner);
    final known = {
      for (final t in [...todo, ...planner])
        if (t.id != null) t.id!,
    };
    // Задача, которой нет ни в снимке вызывающего, ни в том, что мы ему
    // отдавали, — это прилёт синка. Его снимок не свидетельство удаления.
    bool arrived(PomoTask t) =>
        t.id != null && !known.contains(t.id) && !_servedTasks.contains(t.id!);
    final keepTodo = [
      for (final t in doc.todo)
        if (arrived(t)) t,
    ];
    final keepPlanner = [
      for (final t in doc.planner)
        if (arrived(t)) t,
    ];
    doc.todo
      ..clear()
      ..addAll(todo)
      ..addAll(keepTodo);
    doc.planner
      ..clear()
      ..addAll(planner)
      ..addAll(keepPlanner);
    // Только то, что вызывающий реально видел. Если записать сюда и
    // приехавшее, второе подряд сохранение того же устаревшего снимка
    // сочло бы его удалённым — и дыра вернулась бы через один шаг.
    _servedTasks = known;
    await _write(doc, before: before);
    await _mirrorTasks(doc);
    return unit;
  });

  /// Выдать id новым задачам и ВЫБРОСИТЬ повторы.
  ///
  /// Раньше повтор получал свежий id — и любой дубликат, пришедший из
  /// слияния, превращался в отдельную новую задачу, которая расползалась
  /// по всем устройствам. Копии, которым нужен свой id (например, после
  /// «Разбить»), выдают его себе сами на месте.
  List<PomoTask> _withIds(List<PomoTask> list) {
    final seen = <String>{};
    final result = <PomoTask>[];
    for (final t in list) {
      final id = t.id ?? newId();
      if (!seen.add(id)) continue;
      result.add(t.id == null ? t.copyWith(id: id) : t);
    }
    return result;
  }

  /// Одна задача не может лежать сразу в «Сегодня» и в планировщике.
  /// Такие документы существуют — их наплодило прежнее слияние, которое
  /// объединяло два списка независимо. Чиним при чтении: «Сегодня» новее,
  /// туда задачу переносили осознанно.
  bool _dedupeBuckets(_Doc doc) {
    final inTodo = {
      for (final t in doc.todo)
        if (t.id != null) t.id!,
    };
    if (inTodo.isEmpty) return false;
    final cleaned = [
      for (final t in doc.planner)
        if (t.id == null || !inTodo.contains(t.id)) t,
    ];
    if (cleaned.length == doc.planner.length) return false;
    doc.planner
      ..clear()
      ..addAll(cleaned);
    return true;
  }

  List<PomoTask> _tasks(Object? raw) => [
    if (raw is List)
      for (final e in raw.whereType<Map<String, dynamic>>())
        _Doc._taskFromJson(e, legacy: true),
  ];

  // -- журнал -----------------------------------------------------------------

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int dailyGoal) =>
      _guard(() async {
        final doc = await _load();
        return _serve(_dayOf(doc, date, dailyGoal));
      });

  /// Запомнить, какие записи дня вызывающий видел (см. [_servedDays]).
  DayLog _serve(DayLog log) {
    _servedDays[dateKey(log.date)] = {for (final s in log.sessions) s.id};
    return log;
  }

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
    final key = dateKey(log.date);
    final stored = doc.days[key];
    final known = {for (final s in log.sessions) s.id};
    final served = _servedDays[key] ?? const <String>{};
    // Записи, появившиеся после того, как вызывающий прочитал день (синк или
    // только что дотикавший помидор), сохраняем: их отсутствие в его снимке
    // означает «не знал», а не «удалил».
    final arrived = [
      if (stored != null)
        for (final s in stored.sessions)
          if (!known.contains(s.id) && !served.contains(s.id)) s,
    ];
    // Этими полями владеют только атомарные методы InsightRepository.
    final merged = log.copyWith(
      sessions: [...log.sessions, ...arrived],
      episodes: stored?.episodes ?? const [],
      checkIn: stored?.checkIn ?? const CheckIn(),
      ips: stored?.ips ?? const [],
    );
    doc.days[key] = merged;
    _servedDays[key] = known;
    await _write(doc, before: before);
    await _mirrorDay(merged);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> addSession(
    PomoSession session,
    int dailyGoal,
  ) => _guard(() async {
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

  Sprint _sprintOf(_Doc doc, String id, int defaultGoal) {
    final existing = doc.sprints[id];
    if (existing != null) {
      return existing.goal == 0
          ? existing.copyWith(goal: defaultGoal)
          : existing;
    }
    final monday = _mondayOfSprint(id);
    if (monday == null) throw FormatException('Неизвестный спринт: $id');
    return Sprint(
      id: id,
      start: monday,
      goal: defaultGoal,
    );
  }

  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int defaultGoal) =>
      _guard(() async {
        final doc = await _load();
        return _sprintOf(doc, sprintId(now), defaultGoal);
      });

  @override
  Future<Either<Failure, Unit>> saveSprint(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks = const [],
  }) => _guard(() async {
    final doc = await _load();
    final existing = doc.sprints[sprint.id];
    // Снимок вызывающего не владеет ни экспериментом, ни кешем разбора.
    final saved = Sprint(
      id: sprint.id,
      start: sprint.start,
      goal: sprint.goal,
      milestone: sprint.milestone,
      milestoneId: sprint.milestoneId,
      doneWeek: sprint.doneWeek,
      experiment: existing?.experiment,
      review: existing?.review,
    );
    // Факт в документе не хранится — он производный от журнала. Поэтому
    // сравниваем только редактируемые поля и выходим ДО записи и до onSaved:
    // иначе каждый помидор дёргал бы отправку в Drive.
    if (existing != null &&
        existing.goal == sprint.goal &&
        existing.milestone == sprint.milestone &&
        existing.milestoneId == sprint.milestoneId &&
        _sameList(existing.doneWeek, sprint.doneWeek)) {
      await _mirrorSprint(doc, saved, fact, weekTasks);
      return unit;
    }
    doc.sprints[sprint.id] = saved;
    await _write(doc);
    await _mirrorSprint(doc, saved, fact, weekTasks);
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
        final day = doc
            .days[dateKey(DateTime(monday.year, monday.month, monday.day + i))];
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

  // -- эпизоды и наблюдения --------------------------------------------------

  @override
  Future<Either<Failure, Unit>> addEpisode(Episode e) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    // Повторная доставка сигнала с тем же id не создаёт второй эпизод.
    if (doc.days.values.any((d) => d.episodes.any((x) => x.id == e.id))) {
      return unit;
    }
    final day = _dayOf(doc, logicalDate(e.at), 0);
    final updated = day.copyWith(episodes: [...day.episodes, e]);
    doc.days[dateKey(day.date)] = updated;
    await _write(doc, before: before);
    await _mirrorDay(updated);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> updateEpisode(Episode e) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    for (final day in doc.days.values.toList()) {
      if (!day.episodes.any((x) => x.id == e.id)) continue;
      final updated = day.copyWith(
        episodes: [
          for (final x in day.episodes)
            if (x.id != e.id) x,
        ],
      );
      final target = logicalDate(e.at);
      if (dateKey(target) == dateKey(day.date)) {
        final sameDay = day.copyWith(
          episodes: [for (final x in day.episodes) x.id == e.id ? e : x],
        );
        doc.days[dateKey(day.date)] = sameDay;
        await _write(doc, before: before);
        await _mirrorDay(sameDay);
      } else {
        doc.days[dateKey(day.date)] = updated;
        final next = _dayOf(doc, target, 0);
        final moved = next.copyWith(episodes: [...next.episodes, e]);
        doc.days[dateKey(target)] = moved;
        await _write(doc, before: before);
        await _mirrorDay(updated);
        await _mirrorDay(moved);
      }
      return unit;
    }
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> deleteEpisode(String id) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    final changed = <DayLog>[];
    for (final day in doc.days.values.toList()) {
      if (!day.episodes.any((e) => e.id == id)) continue;
      final updated = day.copyWith(
        episodes: [
          for (final e in day.episodes)
            if (e.id != id) e,
        ],
      );
      doc.days[dateKey(day.date)] = updated;
      changed.add(updated);
    }
    if (changed.isEmpty) return unit;
    await _write(doc, before: before);
    for (final day in changed) {
      await _mirrorDay(day);
    }
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> setCheckIn(DateTime day, CheckIn ck) =>
      _guard(() async {
        final doc = await _load();
        final before = doc.ids();
        final log = _dayOf(doc, day, 0);
        final updated = log.copyWith(checkIn: log.checkIn.merge(ck));
        doc.days[dateKey(log.date)] = updated;
        await _write(doc, before: before);
        await _mirrorDay(updated);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> saveIps(DateTime day, List<int> answers) =>
      _guard(() async {
        final doc = await _load();
        final before = doc.ids();
        final log = _dayOf(doc, day, 0);
        final updated = log.copyWith(ips: List<int>.of(answers));
        doc.days[dateKey(log.date)] = updated;
        await _write(doc, before: before);
        await _mirrorDay(updated);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> saveExperiment(
    String sprintId,
    Experiment? exp,
  ) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    final sprint = _sprintOf(
      doc,
      sprintId,
      0,
    ).copyWith(experiment: exp, clearExperiment: exp == null);
    doc.sprints[sprintId] = sprint;
    await _write(doc, before: before);
    await _mirrorStoredSprint(doc, sprint);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> saveReview(
    String sprintId,
    WeekReview review,
  ) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    final sprint = _sprintOf(doc, sprintId, 0).copyWith(review: review);
    doc.sprints[sprintId] = sprint;
    await _write(doc, before: before);
    await _mirrorStoredSprint(doc, sprint);
    return unit;
  });

  Future<void> _mirrorStoredSprint(_Doc doc, Sprint sprint) => _mirrorSprint(
    doc,
    sprint,
    [
      for (final day in doc.days.values)
        if (!day.date.isBefore(sprint.start) && !day.date.isAfter(sprint.end))
          day,
    ]..sort((a, b) => a.date.compareTo(b.date)),
    [
      for (final task in [...doc.todo, ...doc.planner])
        if (task.week) task,
    ],
  );

  // -- курс (направления и вехи) ---------------------------------------------

  @override
  Future<Either<Failure, Course>> loadCourse() => _guard(() async {
    final doc = await _load();
    _servedCourse = {
      for (final d in doc.directions) d.id,
      for (final m in doc.milestones) m.id,
    };
    return (directions: [...doc.directions], milestones: [...doc.milestones]);
  });

  @override
  Future<Either<Failure, Unit>> saveCourse(Course course) => _guard(() async {
    final doc = await _load();
    final before = doc.ids();
    final directions = _withDirIds(course.directions);
    final milestones = _withMilestoneIds(course.milestones);
    final known = {
      for (final d in directions) d.id,
      for (final m in milestones) m.id,
    };
    // Направление или веха, которых нет ни в снимке вызывающего, ни в том,
    // что мы ему отдавали, — это прилёт синка. Его снимок не свидетельство
    // удаления.
    bool arrivedDir(Direction d) =>
        d.id.isNotEmpty &&
        !known.contains(d.id) &&
        !_servedCourse.contains(d.id);
    bool arrivedMile(Milestone m) =>
        m.id.isNotEmpty &&
        !known.contains(m.id) &&
        !_servedCourse.contains(m.id);

    final keepDirs = [
      for (final d in doc.directions)
        if (arrivedDir(d)) d,
    ];
    final keepMiles = [
      for (final m in doc.milestones)
        if (arrivedMile(m)) m,
    ];

    doc.directions
      ..clear()
      ..addAll(directions)
      ..addAll(keepDirs);
    doc.milestones
      ..clear()
      ..addAll(milestones)
      ..addAll(keepMiles);

    _servedCourse = known;
    await _write(doc, before: before);
    await _mirrorCourse(doc);
    return unit;
  });

  List<Direction> _withDirIds(List<Direction> list) {
    final seen = <String>{};
    final result = <Direction>[];
    for (final d in list) {
      final id = d.id.isEmpty ? newId() : d.id;
      if (!seen.add(id)) continue;
      result.add(d.id.isEmpty ? d.copyWith(id: id) : d);
    }
    return result;
  }

  List<Milestone> _withMilestoneIds(List<Milestone> list) {
    final seen = <String>{};
    final result = <Milestone>[];
    for (final m in list) {
      final id = m.id.isEmpty ? newId() : m.id;
      if (!seen.add(id)) continue;
      result.add(m.id.isEmpty ? m.copyWith(id: id) : m);
    }
    return result;
  }

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
    _Doc doc,
    Sprint sprint,
    List<DayLog> fact,
    List<PomoTask> weekTasks,
  ) => _mirror(
    _store.sprintFile(sprint.id),
    _mirrorNote +
        serializeSprint(
          sprint,
          fact,
          weekTasks: weekTasks,
          milestoneText: _milestoneTitle(doc, sprint),
        ),
  );

  /// Текст вехи недели для зеркала. Веха, взятая из лестницы направления,
  /// хранится ссылкой, и `sprint.milestone` у такой недели пуст — без
  /// разворачивания ссылки `Спринты/*.md` терял веху целиком.
  String _milestoneTitle(_Doc doc, Sprint sprint) {
    if (sprint.milestoneId.isEmpty) return sprint.milestone;
    for (final m in doc.milestones) {
      if (m.id == sprint.milestoneId) return m.title;
    }
    return sprint.milestone;
  }

  /// Пустой курс не зеркалим совсем: пока направлений нет, файл «Курс.md» в
  /// валте — просто шум, а лишняя файловая операция на каждый прилёт синка
  /// ещё и гоняется с чтением валта.
  Future<void> _mirrorCourse(_Doc doc) async {
    if (doc.directions.isEmpty && doc.milestones.isEmpty) return;
    await _mirror(
      _store.courseFile(),
      _mirrorNote + serializeCourse(doc.directions, doc.milestones),
    );
  }

  /// После прилёта удалённой версии — переписать зеркала целиком.
  Future<void> _mirrorAll(_Doc doc) async {
    await _mirrorTasks(doc);
    for (final log in doc.days.values) {
      await _mirrorDay(log);
    }
    await _mirrorCourse(doc);
  }

  // Сериализуем и чтение снимка, и его изменение: одной очереди _dump мало.
  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) =>
      _serial(() async {
        try {
          return Either.right(await body());
        } on FileSystemException catch (e) {
          return Either.left(
            StorageFailure('Файловая ошибка: ${e.message} ${e.path ?? ''}'),
          );
        } on FormatException catch (e) {
          return Either.left(ParseFailure('Ошибка разбора: ${e.message}'));
        }
      });
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
    required this.extra,
    required this.directions,
    required this.milestones,
  });

  factory _Doc.empty() => _Doc(
    todo: [],
    planner: [],
    days: {},
    sprints: {},
    graves: {},
    rollover: {},
    extra: {},
    directions: [],
    milestones: [],
  );

  /// Ключи, которые _Doc знает. Всё остальное проносится через [extra]:
  /// mergeData специально сохраняет незнакомые секции победителя, но decode →
  /// encode в applyRemote стирал их в ту же секунду, и защита не работала.
  static const _known = {
    'schema',
    'todo',
    'planner',
    'days',
    'sprints',
    'graves',
    'rollover',
    'timer',
    'dirs',
    'miles',
  };

  factory _Doc.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return _Doc.empty();
    final doc = _Doc.empty();
    for (final e in json.entries) {
      if (!_known.contains(e.key)) doc.extra[e.key] = e.value;
    }
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
          milestoneId:
              s['milestoneId'] as String? ?? (s['mid'] as String? ?? ''),
          doneWeek: [
            if (s['done'] is List) ...(s['done'] as List).whereType<String>(),
          ],
          experiment: _experimentFrom(s['exp']),
          review: _reviewFrom(s['ai']),
        );
      }
    }
    final dirs = json['dirs'];
    if (dirs is List) {
      for (final e in dirs.whereType<Map<String, dynamic>>()) {
        doc.directions.add(_directionFrom(e));
      }
    }
    final miles = json['miles'];
    if (miles is List) {
      for (final e in miles.whereType<Map<String, dynamic>>()) {
        doc.milestones.add(_milestoneFrom(e));
      }
    }
    final graves = json['graves'];
    if (graves is Map<String, dynamic>) {
      for (final e in graves.entries) {
        if (e.value is String) doc.graves[e.key] = e.value as String;
      }
    }
    final timer = json['timer'];
    if (timer is Map<String, dynamic>) doc.timer = timer;
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
  final List<Direction> directions;
  final List<Milestone> milestones;

  /// Секции будущих версий, о которых этот код ещё не знает.
  final Map<String, dynamic> extra;

  /// Снимок таймера последнего устройства, которое его трогало.
  Map<String, dynamic>? timer;

  /// Все живые id — база для диффа надгробий.
  Set<String> ids() => {
    for (final t in todo)
      if (t.id != null) t.id!,
    for (final t in planner)
      if (t.id != null) t.id!,
    for (final d in days.values)
      for (final s in d.sessions) s.id,
    for (final d in days.values)
      for (final e in d.episodes) e.id,
    for (final d in directions) d.id,
    for (final m in milestones) m.id,
  };

  String encode() => jsonEncode({
    ...extra,
    'schema': 2,
    'todo': [for (final t in todo) _taskJson(t)],
    'planner': [for (final t in planner) _taskJson(t)],
    'days': {
      for (final e in days.entries)
        e.key: {
          'goal': e.value.goal,
          's': [for (final s in e.value.sessions) _sessionJson(s)],
          if (e.value.notes.isNotEmpty) 'n': e.value.notes,
          if (e.value.episodes.isNotEmpty)
            'e': [
              for (final episode in e.value.episodes) _episodeJson(episode),
            ],
          if (!e.value.checkIn.isEmpty) 'ck': _checkInJson(e.value.checkIn),
          if (e.value.ips.isNotEmpty) 'ips': e.value.ips,
        },
    },
    'sprints': {
      for (final e in sprints.entries)
        e.key: {
          'goal': e.value.goal,
          if (e.value.milestone.isNotEmpty) 'milestone': e.value.milestone,
          if (e.value.milestoneId.isNotEmpty)
            'milestoneId': e.value.milestoneId,
          if (e.value.doneWeek.isNotEmpty) 'done': e.value.doneWeek,
          if (e.value.experiment case final experiment?)
            'exp': _experimentJson(experiment),
          if (e.value.review case final review?) 'ai': _reviewJson(review),
        },
    },
    'graves': graves,
    if (rollover.isNotEmpty) 'rollover': rollover,
    if (timer != null) 'timer': timer,
    if (directions.isNotEmpty)
      'dirs': [for (final d in directions) _directionJson(d)],
    if (milestones.isNotEmpty)
      'miles': [for (final m in milestones) _milestoneJson(m)],
  });

  static List<PomoTask> _taskList(Object? raw) => [
    if (raw is List)
      for (final e in raw.whereType<Map<String, dynamic>>()) _taskFromJson(e),
  ];

  static PomoTask _taskFromJson(Map<String, dynamic> j, {bool legacy = false}) {
    final minutes = (j['min'] as num?)?.toInt() ?? 1;
    final due = j['due'];
    return PomoTask(
      id: j['id'] as String?,
      description: j['desc'] as String? ?? '',
      category: j['cat'] as String? ?? 'прочее',
      durationMinutes: legacy ? max(1, minutes) : minutes.clamp(1, 1 << 30),
      due: due is String ? DateTime.tryParse(due) : null,
      frog: j['frog'] == true,
      week: j['week'] == true,
      milestoneId: j['ms'] as String? ?? '',
      firstStep: j['fs'] as String? ?? '',
      cue: j['cue'] as String? ?? '',
      cueAt: j['cueAt'] as String? ?? '',
      deferrals: (j['df'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, dynamic> _taskJson(PomoTask t) => {
    'id': t.id,
    'desc': t.description,
    'cat': t.category,
    'min': t.durationMinutes,
    if (t.due != null) 'due': dateKey(t.due!),
    if (t.frog) 'frog': true,
    if (t.week) 'week': true,
    if (t.milestoneId.isNotEmpty) 'ms': t.milestoneId,
    if (t.firstStep.isNotEmpty) 'fs': t.firstStep,
    if (t.cue.isNotEmpty) 'cue': t.cue,
    if (t.cueAt.isNotEmpty) 'cueAt': t.cueAt,
    if (t.deferrals != 0) 'df': t.deferrals,
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
      episodes: [
        if (json['e'] is List)
          for (final e in (json['e'] as List).whereType<Map<String, dynamic>>())
            _episodeFrom(date, e),
      ],
      checkIn: _checkInFrom(json['ck']),
      ips: [if (json['ips'] is List) ...(json['ips'] as List).whereType<int>()],
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
        hour < dayStartHour ? date.day + 1 : date.day,
        hour,
        minute,
      ),
      minutes: (j['m'] as num?)?.toInt() ?? 1,
      category: j['c'] as String? ?? '',
      task: j['d'] as String? ?? '',
      taskId: j['tid'] as String? ?? '',
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
    if (s.taskId.isNotEmpty) 'tid': s.taskId,
    if (s.delayMinutes != 0) 'dl': s.delayMinutes,
    if (s.interruptions != 0) 'in': s.interruptions,
    if (s.manual) 'man': true,
    if (s.frog) 'frog': true,
  };

  static T? _enumFrom<T extends Enum>(List<T> values, Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static Episode _episodeFrom(DateTime date, Map<String, dynamic> j) {
    final parts = '${j['t']}'.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return Episode(
      id: j['id'] as String? ?? newId(),
      at: DateTime(
        date.year,
        date.month,
        hour < dayStartHour ? date.day + 1 : date.day,
        hour,
        minute,
      ),
      source: _enumFrom(EpisodeSource.values, j['src']),
      taskId: j['tid'] as String? ?? '',
      task: j['d'] as String? ?? '',
      category: j['c'] as String? ?? '',
      cause: _enumFrom(Cause.values, j['cause']),
      strategy: _enumFrom(StrategyKind.values, j['st']),
      thought: j['th'] as String? ?? '',
      fact: j['fact'] as String? ?? '',
      alt: j['alt'] as String? ?? '',
      app: j['app'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _episodeJson(Episode e) => {
    'id': e.id,
    't': '${two(e.at.hour)}:${two(e.at.minute)}',
    if (e.source case final source?) 'src': source.name,
    if (e.taskId.isNotEmpty) 'tid': e.taskId,
    if (e.task.isNotEmpty) 'd': e.task,
    if (e.category.isNotEmpty) 'c': e.category,
    if (e.cause case final cause?) 'cause': cause.name,
    if (e.strategy case final strategy?) 'st': strategy.name,
    if (e.thought.isNotEmpty) 'th': e.thought,
    if (e.fact.isNotEmpty) 'fact': e.fact,
    if (e.alt.isNotEmpty) 'alt': e.alt,
    if (e.app.isNotEmpty) 'app': e.app,
  };

  static CheckIn _checkInFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return const CheckIn();
    int? rating(Object? value) =>
        value is int && value >= 1 && value <= 5 ? value : null;
    return CheckIn(
      sleep: rating(raw['sl']),
      energy: rating(raw['en']),
      mood: rating(raw['md']),
    );
  }

  static Map<String, dynamic> _checkInJson(CheckIn ck) => {
    if (ck.sleep != null) 'sl': ck.sleep,
    if (ck.energy != null) 'en': ck.energy,
    if (ck.mood != null) 'md': ck.mood,
  };

  static Experiment? _experimentFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final strategy = _enumFrom(StrategyKind.values, raw['st']);
    final metric = _enumFrom(InsightMetric.values, raw['m']);
    // Не подменяем неизвестный способ или метрику произвольным значением.
    if (strategy == null || metric == null) return null;
    return Experiment(
      hypothesis: raw['h'] as String? ?? '',
      strategy: strategy,
      metric: metric,
      baseline: (raw['base'] as num?)?.toDouble(),
      verdict: _enumFrom(Verdict.values, raw['v']),
    );
  }

  static Map<String, dynamic> _experimentJson(Experiment exp) => {
    if (exp.hypothesis.isNotEmpty) 'h': exp.hypothesis,
    'st': exp.strategy.name,
    'm': exp.metric.name,
    // Ноль — известное значение базы, а не отсутствие измерения.
    if (exp.baseline != null) 'base': exp.baseline,
    if (exp.verdict case final verdict?) 'v': verdict.name,
  };

  static WeekReview? _reviewFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final at = raw['at'];
    final date = at is String ? DateTime.tryParse(at) : null;
    if (date == null) return null;
    return WeekReview(
      at: date,
      summary: raw['summary'] as String? ?? '',
      patterns: [
        if (raw['p'] is List)
          for (final p in (raw['p'] as List).whereType<Map<String, dynamic>>())
            (text: p['t'] as String? ?? '', evidence: p['e'] as String? ?? ''),
      ],
    );
  }

  static Map<String, dynamic> _reviewJson(WeekReview review) => {
    'at': review.at.toIso8601String(),
    if (review.summary.isNotEmpty) 'summary': review.summary,
    if (review.patterns.isNotEmpty)
      'p': [
        for (final p in review.patterns)
          {
            if (p.text.isNotEmpty) 't': p.text,
            if (p.evidence.isNotEmpty) 'e': p.evidence,
          },
      ],
  };

  static Direction _directionFrom(Map<String, dynamic> j) {
    final st = switch (j['st'] as String?) {
      'paused' => DirectionStatus.paused,
      'done' => DirectionStatus.done,
      _ => DirectionStatus.active,
    };
    final hor = j['hor'];
    return Direction(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      why: j['why'] as String? ?? '',
      note: j['note'] as String? ?? '',
      horizon: hor is String ? DateTime.tryParse(hor) : null,
      status: st,
      order: (j['ord'] as num?)?.toInt() ?? 0,
      categories: [
        if (j['cats'] is List) ...(j['cats'] as List).whereType<String>(),
      ],
    );
  }

  static Map<String, dynamic> _directionJson(Direction d) => {
    'id': d.id,
    'name': d.name,
    if (d.why.isNotEmpty) 'why': d.why,
    if (d.note.isNotEmpty) 'note': d.note,
    if (d.horizon != null) 'hor': dateKey(d.horizon!),
    'st': d.status.name,
    'ord': d.order,
    if (d.categories.isNotEmpty) 'cats': d.categories,
  };

  static Milestone _milestoneFrom(Map<String, dynamic> j) {
    final wa = j['wa'];
    return Milestone(
      id: j['id'] as String? ?? '',
      directionId: j['dir'] as String? ?? '',
      title: j['t'] as String? ?? '',
      order: (j['ord'] as num?)?.toInt() ?? 0,
      doneSprint: j['ws'] as String? ?? '',
      doneAt: wa is String ? DateTime.tryParse(wa) : null,
      proofs: [if (j['pf'] is List) ...(j['pf'] as List).whereType<String>()],
    );
  }

  static Map<String, dynamic> _milestoneJson(Milestone m) => {
    'id': m.id,
    'dir': m.directionId,
    't': m.title,
    'ord': m.order,
    if (m.doneSprint.isNotEmpty) 'ws': m.doneSprint,
    if (m.doneAt != null) 'wa': dateKey(m.doneAt!),
    if (m.proofs.isNotEmpty) 'pf': m.proofs,
  };
}
