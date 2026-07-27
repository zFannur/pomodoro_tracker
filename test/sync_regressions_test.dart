import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';
import 'package:pomodoro_tracker/data/json_data_repository.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/data/timer_state_store.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

/// Регрессии на дефекты из BUGS.md. Все они раньше проходили мимо тестов —
/// именно поэтому и дожили до продакшена.
void main() {
  late Directory vaultDir;
  late Directory dataDir;
  late VaultStore store;

  JsonDataRepository repo() => JsonDataRepository(
    store,
    mirrorEnabled: () => false,
    dirProvider: () async => dataDir.path,
  );

  setUp(() {
    vaultDir = Directory.systemTemp.createTempSync('pomo_vault');
    dataDir = Directory.systemTemp.createTempSync('pomo_data');
    store = VaultStore(vaultDir.path);
  });

  tearDown(() {
    vaultDir.deleteSync(recursive: true);
    dataDir.deleteSync(recursive: true);
  });

  PomoTask t(String d, {String? id}) =>
      PomoTask(id: id, description: d, category: 'кат', durationMinutes: 25);

  PomoSession s(String id, int hour) => PomoSession(
    id: id,
    start: DateTime(2026, 7, 20, hour),
    minutes: 25,
    category: 'кат',
    task: id,
  );

  String remoteDoc({
    List<String> todo = const [],
    Map<String, List<String>> days = const {},
  }) => jsonEncode({
    'schema': 2,
    'todo': [
      for (final id in todo) {'id': id, 'desc': id, 'cat': 'кат', 'min': 25},
    ],
    'planner': <Object>[],
    'days': {
      for (final e in days.entries)
        e.key: {
          'goal': 10,
          's': [
            for (final id in e.value)
              {'id': id, 't': '09:00', 'm': 25, 'c': 'кат', 'd': id},
          ],
        },
    },
    'sprints': <String, Object>{},
    'graves': <String, Object>{},
  });

  // -- B2: гонка записи ------------------------------------------------------

  test('B2: параллельные applyRemote и saveTasks не бьют data.json', () async {
    final r = repo();
    await r.saveTasks(
      TasksFile(
        todo: [t('первая', id: 'a')],
        planner: const [],
      ),
    );

    // Без await между ними — ровно тот случай, когда синк применяет удалённую
    // версию, а пользователь в этот момент жмёт кнопку.
    final f1 = r.applyRemote(remoteDoc(todo: ['a', 'b']));
    final f2 = r.saveTasks(
      TasksFile(
        todo: [t('первая', id: 'a')],
        planner: const [],
      ),
    );
    await Future.wait([f1, f2]);

    final raw = await File(
      '${dataDir.path}${Platform.pathSeparator}data.json',
    ).readAsString();
    expect(
      () => jsonDecode(raw),
      returnsNormally,
      reason: 'на диске должен лежать валидный JSON, а не склейка двух',
    );
    // И временные файлы не должны оставаться мусором.
    final tmps = dataDir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.tmp'),
    );
    expect(tmps, isEmpty);
  });

  // -- B1: окно между applyRemote и перечитыванием стейта ---------------------

  test('B1: запись доsync-снимка не хоронит приехавшие задачи', () async {
    final r = repo();
    await r.saveTasks(
      TasksFile(
        todo: [t('своя', id: 'a')],
        planner: const [],
      ),
    );
    await r.load(); // вызывающий видит только «a»

    // Синк принёс ещё одну задачу.
    await r.applyRemote(remoteDoc(todo: ['a', 'b']));

    // Кубит ещё не перечитал стейт и сохраняет то, что помнит.
    await r.saveTasks(
      TasksFile(
        todo: [t('своя', id: 'a')],
        planner: const [],
      ),
    );

    final doc =
        jsonDecode(
              await File(
                '${dataDir.path}${Platform.pathSeparator}data.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(
      doc['graves'],
      isNot(contains('b')),
      reason: 'приехавшая задача не удалялась пользователем — хоронить нельзя',
    );
    final after = (await r.load()).getOrElse(
      (_) => const TasksFile(todo: [], planner: []),
    );
    expect(after.todo.map((e) => e.id), containsAll(['a', 'b']));
  });

  test('B1: ВТОРОЕ подряд сохранение того же снимка тоже не хоронит', () async {
    final r = repo();
    await r.saveTasks(
      TasksFile(
        todo: [t('своя', id: 'a')],
        planner: const [],
      ),
    );
    await r.load();
    await r.applyRemote(remoteDoc(todo: ['a', 'b']));

    final stale = TasksFile(
      todo: [t('своя', id: 'a')],
      planner: const [],
    );
    await r.saveTasks(stale);
    await r.saveTasks(stale);

    final doc =
        jsonDecode(
              await File(
                '${dataDir.path}${Platform.pathSeparator}data.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(doc['graves'], isNot(contains('b')));
    final after = (await r.load()).getOrElse(
      (_) => const TasksFile(todo: [], planner: []),
    );
    expect(after.todo.map((e) => e.id), containsAll(['a', 'b']));
  });

  test('B1: запись доsync-снимка дня не хоронит приехавшие помидоры', () async {
    final r = repo();
    final day = DateTime(2026, 7, 20);
    await r.saveDay(DayLog(date: day, goal: 10, sessions: [s('x', 9)]));
    await r.day(day, 10); // вызывающий видит только «x»

    await r.applyRemote(
      remoteDoc(
        days: {
          '2026-07-20': ['x', 'y'],
        },
      ),
    );

    // Пользователь правит журнал по устаревшему списку.
    await r.saveDay(DayLog(date: day, goal: 10, sessions: [s('x', 9)]));

    final log = (await r.day(
      day,
      10,
    )).getOrElse((_) => DayLog(date: day, goal: 10, sessions: const []));
    expect(
      log.sessions.map((e) => e.id),
      containsAll(['x', 'y']),
      reason: 'помидор с другого устройства не должен исчезать',
    );
  });

  test('B1: реальное удаление по-прежнему хоронится', () async {
    final r = repo();
    await r.saveTasks(
      TasksFile(
        todo: [
          t('a', id: 'a'),
          t('b', id: 'b'),
        ],
        planner: const [],
      ),
    );
    await r.load();
    await r.saveTasks(
      TasksFile(
        todo: [t('a', id: 'a')],
        planner: const [],
      ),
    );

    final doc =
        jsonDecode(
              await File(
                '${dataDir.path}${Platform.pathSeparator}data.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect((doc['graves'] as Map).keys, contains('b'));
  });

  // -- B16: порядок сессий на границе логического дня ------------------------

  test('B16: ночная сессия после слияния остаётся в конце дня', () {
    Map<String, dynamic> sess(String id, String time) => {
      'id': id,
      't': time,
      'm': 25,
      'c': 'x',
      'd': id,
    };
    String d(List<Map<String, dynamic>> list) => jsonEncode({
      'schema': 2,
      'days': {
        '2026-07-20': {'goal': 10, 's': list},
      },
    });

    final merged =
        jsonDecode(
              mergeData(
                d([sess('вечер', '23:40')]),
                d([sess('ночь', '00:55')]),
                localWins: true,
              ),
            )
            as Map<String, dynamic>;
    final order = [
      for (final e in (merged['days'] as Map)['2026-07-20']['s'] as List)
        (e as Map)['id'] as String,
    ];
    expect(order, ['вечер', 'ночь']);
  });

  // -- B17: веха спринта ------------------------------------------------------

  test('B17: непустая веха переживает победителя без ключа milestone', () {
    String d(Map<String, dynamic> sprint) => jsonEncode({
      'schema': 2,
      'sprints': {'2026-W30': sprint},
    });

    final merged =
        jsonDecode(
              mergeData(
                d({'goal': 40}), // encode опускает пустую веху
                d({'goal': 40, 'milestone': 'Coster Go на Кворк'}),
                localWins: true,
              ),
            )
            as Map<String, dynamic>;
    expect(
      (merged['sprints'] as Map)['2026-W30']['milestone'],
      'Coster Go на Кворк',
    );
  });

  // -- B23: незнакомые секции ------------------------------------------------

  test('B23: секция будущей версии переживает applyRemote', () async {
    final r = repo();
    final withExtra =
        jsonDecode(remoteDoc(todo: ['a'])) as Map<String, dynamic>;
    withExtra['somethingNew'] = {'k': 'v'};
    await r.applyRemote(jsonEncode(withExtra));

    final doc =
        jsonDecode(
              await File(
                '${dataDir.path}${Platform.pathSeparator}data.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(doc['somethingNew'], {'k': 'v'});
  });

  // -- B20: frontmatter под шапкой зеркала ------------------------------------

  test('B20: parseSprint читает то, что реально пишется на диск', () {
    final sprint = Sprint(
      id: '2026-W30',
      start: DateTime(2026, 7, 20),
      goal: 40,
      milestone: 'веха недели',
    );
    const note =
        '<!-- Зеркало Помодоро Трекера: правки здесь не читаются. -->\n';
    final onDisk = note + serializeSprint(sprint, const []);

    final parsed = parseSprint(onDisk, '2026-W30', DateTime(2026, 7, 20), 0);
    expect(parsed.goal, 40);
    expect(parsed.milestone, 'веха недели');
  });

  // -- B13/B22: снимок таймера ------------------------------------------------

  test('B13: снимок таймера возит overtime и startedAt', () {
    final started = DateTime(2026, 7, 20, 10);
    final snap = TimerSnapshot(
      mode: 'pomodoro',
      run: 'running',
      remaining: 0,
      total: 1500,
      series: 2,
      interruptions: 1,
      delaysMs: 0,
      overtime: 420,
      startedAt: started,
      savedAt: DateTime(2026, 7, 20, 10, 32),
    );
    final back = TimerSnapshot.fromJson(
      jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>,
    )!;
    expect(back.overtime, 420);
    expect(back.startedAt, started);
  });

  // -- B9: слияние снимка таймера ---------------------------------------------

  test('B9: побеждает более свежий снимок таймера, а не localWins', () {
    String d(int savedAt, String device) => jsonEncode({
      'schema': 2,
      'timer': {'device': device, 'savedAt': savedAt, 'run': 'running'},
    });

    final merged =
        jsonDecode(mergeData(d(100, 'пк'), d(200, 'телефон'), localWins: true))
            as Map<String, dynamic>;
    expect((merged['timer'] as Map)['device'], 'телефон');
  });

  // -- B11: rollover в документе ----------------------------------------------

  test('B11: отметки ролловера живут в синхронизируемом документе', () async {
    final r = repo();
    await r.markRollover(day: '2026-07-20', week: '2026-W30');
    final marks = (await r.rollover()).getOrElse(
      (_) => (day: null, week: null),
    );
    expect(marks.day, '2026-07-20');
    expect(marks.week, '2026-W30');

    final doc =
        jsonDecode(
              await File(
                '${dataDir.path}${Platform.pathSeparator}data.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(doc['rollover'], {'day': '2026-07-20', 'week': '2026-W30'});
  });

  // -- B19: детерминированные id при миграции из зеркала -----------------------

  test('B19: две миграции одного Задачи.md дают одинаковые id', () async {
    await store.write(
      store.tasksFile(),
      serializeTasksFile(
        TasksFile(todo: [t('первая'), t('вторая')], planner: const []),
      ),
    );

    final first = (await repo().load()).getOrElse(
      (_) => const TasksFile(todo: [], planner: []),
    );
    // Второе «устройство»: свой каталог данных, тот же валт.
    final otherDir = Directory.systemTemp.createTempSync('pomo_data2');
    addTearDown(() => otherDir.deleteSync(recursive: true));
    final second = (await JsonDataRepository(
      store,
      mirrorEnabled: () => false,
      dirProvider: () async => otherDir.path,
    ).load()).getOrElse((_) => const TasksFile(todo: [], planner: []));

    expect(
      first.todo.map((e) => e.id).toList(),
      second.todo.map((e) => e.id).toList(),
      reason: 'иначе после синка каждая задача удвоится',
    );
  });

  // -- B15: настенное время ----------------------------------------------------

  test('B15: clock подменяем — значит таймер можно двигать в тестах', () {
    final base = DateTime(2026, 7, 20, 10);
    withClock(Clock.fixed(base), () {
      expect(clock.now(), base);
    });
  });
}
