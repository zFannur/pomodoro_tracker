import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';
import 'package:pomodoro_tracker/data/json_data_repository.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';

Map<String, dynamic> decode(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

Map<String, dynamic> direction(
  String id, {
  String name = '',
  int order = 0,
  List<String> categories = const [],
  String status = 'active',
  String? horizon,
  String note = '',
}) => {
  'id': id,
  'name': name.isEmpty ? id : name,
  'ord': order,
  if (note.isNotEmpty) 'note': note,
  'hor': ?horizon,
  'st': status,
  if (categories.isNotEmpty) 'cats': categories,
};

Map<String, dynamic> milestone(
  String id,
  String directionId, {
  String title = '',
  int order = 0,
  String? doneSprint,
  String? doneAt,
  List<String>? proofs,
}) => {
  'id': id,
  'dir': directionId,
  't': title.isEmpty ? id : title,
  'ord': order,
  'ws': ?doneSprint,
  'wa': ?doneAt,
  if (proofs != null && proofs.isNotEmpty) 'pf': proofs,
};

String doc({
  List<Map<String, dynamic>> todo = const [],
  List<Map<String, dynamic>> planner = const [],
  Map<String, dynamic> days = const {},
  Map<String, dynamic> sprints = const {},
  Map<String, dynamic> graves = const {},
  Map<String, dynamic> rollover = const {},
  List<Map<String, dynamic>>? dirs,
  List<Map<String, dynamic>>? miles,
  Map<String, dynamic> extra = const {},
}) => jsonEncode({
  'schema': 2,
  'todo': todo,
  'planner': planner,
  'days': days,
  'sprints': sprints,
  'graves': graves,
  'rollover': rollover,
  'dirs': ?dirs,
  'miles': ?miles,
  ...extra,
});

List<String> ids(Object? raw) => [
  if (raw is List)
    for (final e in raw) (e as Map<String, dynamic>)['id'] as String,
];

void main() {
  group('слияние направлений (dirs)', () {
    test('направления объединяются по id, порядок победителя первым', () {
      final local = doc(
        dirs: [
          direction('d1', name: 'd1-local', order: 1),
          direction('d2', name: 'd2-local', order: 2),
        ],
      );
      final remote = doc(
        dirs: [
          direction('d2', name: 'd2-remote', order: 2),
          direction('d1', name: 'd1-remote', order: 1),
        ],
      );

      final merged = decode(mergeData(local, remote, localWins: true));
      expect(ids(merged['dirs']), ['d1', 'd2']);
      expect(
        (merged['dirs'] as List).first['name'],
        'd1-local',
        reason: 'побеждает версия победителя',
      );
    });

    test('направление, которого нет у победителя, дописывается в конец', () {
      final winner = doc(
        dirs: [direction('d1', name: 'первое')],
      );
      final loser = doc(
        dirs: [
          direction('d1', name: 'старое'),
          direction('d2', name: 'новое от другого устройства'),
        ],
      );

      final merged = decode(mergeData(winner, loser, localWins: true));
      expect(ids(merged['dirs']), ['d1', 'd2']);
      expect(
        (merged['dirs'] as List).last['name'],
        'новое от другого устройства',
      );
    });

    test('похороненное направление не воскресает после слияния (delete-wins)', () {
      for (final localWins in [true, false]) {
        final withGrave = doc(
          dirs: [direction('d2')],
          graves: {'d1': '2026-07-20T10:00:00.000Z'},
        );
        final withAlive = doc(
          dirs: [direction('d1'), direction('d2')],
        );

        final merged = decode(
          mergeData(
            localWins ? withGrave : withAlive,
            localWins ? withAlive : withGrave,
            localWins: localWins,
          ),
        );
        expect(
          ids(merged['dirs']),
          ['d2'],
          reason: 'localWins=$localWins: d1 должно быть удалено',
        );
      }
    });
  });

  group('слияние вех (miles)', () {
    test('вехи объединяются по id, порядок победителя первым', () {
      final local = doc(
        miles: [
          milestone('m1', 'd1', title: 'm1-local'),
          milestone('m2', 'd1', title: 'm2-local'),
        ],
      );
      final remote = doc(
        miles: [
          milestone('m2', 'd1', title: 'm2-remote'),
          milestone('m1', 'd1', title: 'm1-remote'),
        ],
      );

      final merged = decode(mergeData(local, remote, localWins: true));
      expect(ids(merged['miles']), ['m1', 'm2']);
      expect(
        (merged['miles'] as List).first['t'],
        'm1-local',
        reason: 'побеждает версия победителя',
      );
    });

    test('веха, которой нет у победителя, дописывается в конец', () {
      final winner = doc(
        miles: [milestone('m1', 'd1', title: 'первая')],
      );
      final loser = doc(
        miles: [
          milestone('m1', 'd1', title: 'старая'),
          milestone('m2', 'd1', title: 'вторая'),
        ],
      );

      final merged = decode(mergeData(winner, loser, localWins: true));
      expect(ids(merged['miles']), ['m1', 'm2']);
      expect((merged['miles'] as List).last['t'], 'вторая');
    });

    test('похороненная веха не воскресает после слияния (delete-wins)', () {
      for (final localWins in [true, false]) {
        final withGrave = doc(
          miles: [milestone('m2', 'd1')],
          graves: {'m1': '2026-07-20T10:00:00.000Z'},
        );
        final withAlive = doc(
          miles: [milestone('m1', 'd1'), milestone('m2', 'd1')],
        );

        final merged = decode(
          mergeData(
            localWins ? withGrave : withAlive,
            localWins ? withAlive : withGrave,
            localWins: localWins,
          ),
        );
        expect(
          ids(merged['miles']),
          ['m2'],
          reason: 'localWins=$localWins: m1 должно быть удалено',
        );
      }
    });

    test('proofs двух устройств объединяются, а не теряются; дубликат по значению схлопывается', () {
      final local = doc(
        miles: [
          milestone(
            'm1',
            'd1',
            title: 'Веха 1',
            proofs: [
              '✅ 16.09 Настроить оплату #проекты',
              '✅ 17.09 Общий пункт #проекты',
            ],
          ),
        ],
      );
      final remote = doc(
        miles: [
          milestone(
            'm1',
            'd1',
            title: 'Веха 1',
            proofs: [
              '✅ 17.09 Общий пункт #проекты',
              '✅ 18.09 Запустить рекламу #маркетинг',
            ],
          ),
        ],
      );

      final merged = decode(mergeData(local, remote, localWins: true));
      final miles = merged['miles'] as List;
      final m1 = miles.first as Map<String, dynamic>;
      expect(m1['pf'], [
        '✅ 16.09 Настроить оплату #проекты',
        '✅ 17.09 Общий пункт #проекты',
        '✅ 18.09 Запустить рекламу #маркетинг',
      ]);
    });
  });

  group('milestoneId в спринте', () {
    test('milestoneId спринта берётся у победителя', () {
      final local = doc(
        sprints: {
          '2026-W30': {'goal': 40, 'milestoneId': 'm-winner'},
        },
      );
      final remote = doc(
        sprints: {
          '2026-W30': {'goal': 50, 'milestoneId': 'm-loser'},
        },
      );

      final merged = decode(mergeData(local, remote, localWins: true));
      final sprint = merged['sprints']['2026-W30'] as Map<String, dynamic>;
      expect(sprint['milestoneId'], 'm-winner');
    });

    test('milestoneId НЕ исчезает, если у победителя этого ключа нет вообще', () {
      // Победитель не имеет ключа milestoneId (старый клиент или не трогал веху)
      final winner = doc(
        sprints: {
          '2026-W30': {'goal': 40},
        },
      );
      // Проигравший имеет milestoneId
      final loser = doc(
        sprints: {
          '2026-W30': {'goal': 30, 'milestoneId': 'm-important'},
        },
      );

      final merged = decode(mergeData(winner, loser, localWins: true));
      final sprint = merged['sprints']['2026-W30'] as Map<String, dynamic>;
      expect(
        sprint['milestoneId'],
        'm-important',
        reason: 'ключ не должен затираться отсутствием ключа у победителя',
      );
    });
  });

  group('JsonDataRepository и обратная совместимость', () {
    late Directory vaultDir;
    late Directory dataDir;
    late VaultStore store;

    JsonDataRepository repo() => JsonDataRepository(
      store,
      mirrorEnabled: () => true,
      dirProvider: () async => dataDir.path,
    );

    setUp(() {
      vaultDir = Directory.systemTemp.createTempSync('pomo_vault_course');
      dataDir = Directory.systemTemp.createTempSync('pomo_data_course');
      store = VaultStore(vaultDir.path);
    });

    tearDown(() {
      vaultDir.deleteSync(recursive: true);
      dataDir.deleteSync(recursive: true);
    });

    test('старый data.json без ключей dirs/miles читается без ошибок и после записи ничего не теряет', () async {
      final file = File('${dataDir.path}/data.json');
      file.writeAsStringSync(
        jsonEncode({
          'schema': 2,
          'todo': [
            {'id': 't1', 'desc': 'дело', 'cat': 'прочее', 'min': 25},
          ],
          'planner': <Object>[],
          'days': {},
          'sprints': {},
          'graves': {},
        }),
      );

      final r = repo();
      final course = (await r.loadCourse()).getOrElse((f) => fail(f.message));
      expect(course.directions, isEmpty);
      expect(course.milestones, isEmpty);

      // Чтение задач тоже работает
      final tasks = (await r.load()).getOrElse((f) => fail(f.message));
      expect(tasks.todo.single.description, 'дело');

      // Перезапись задач ничего не ломает и не теряет
      await r.saveTasks(tasks);
      final rawAfter = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(rawAfter['schema'], 2);
      expect((rawAfter['todo'] as List).single['desc'], 'дело');
    });

    test('round-trip курса: сохранение и загрузка направлений и вех', () async {
      final r = repo();
      final d = Direction(
        id: 'd1',
        name: 'Новый продукт',
        note: 'Заметка Obsidian',
        horizon: DateTime(2026, 12, 1),
        status: DirectionStatus.active,
        order: 1,
        categories: const ['продукт', 'код'],
      );
      final m = Milestone(
        id: 'm1',
        directionId: 'd1',
        title: 'Первый релиз',
        order: 1,
        doneSprint: '2026-W30',
        doneAt: DateTime(2026, 7, 25),
      );

      await r.saveCourse((directions: [d], milestones: [m]));

      final loaded = (await repo().loadCourse()).getOrElse((f) => fail(f.message));
      expect(loaded.directions.single, d);
      expect(loaded.milestones.single, m);
    });

    test('удаление направления попадает в надгробия', () async {
      final r = repo();
      final d1 = Direction(id: 'd1', name: 'Направление 1');
      final d2 = Direction(id: 'd2', name: 'Направление 2');
      await r.saveCourse((directions: [d1, d2], milestones: []));

      // Удаляем d1
      await r.saveCourse((directions: [d2], milestones: []));

      final file = File('${dataDir.path}/data.json');
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final graves = doc['graves'] as Map<String, dynamic>;
      expect(graves.containsKey('d1'), isTrue, reason: 'удалённое направление должно попасть в graves');
    });

    test('round-trip вехи с proofs и задачи с milestoneId (ms/pf)', () async {
      final r = repo();
      final d = Direction(id: 'd1', name: 'Фокус');
      final m = Milestone(
        id: 'm1',
        directionId: 'd1',
        title: 'Первый релиз',
        proofs: const ['✅ 16.09 Сделать фичу #код'],
      );
      await r.saveCourse((directions: [d], milestones: [m]));

      final loadedCourse =
          (await r.loadCourse()).getOrElse((f) => fail(f.message));
      expect(loadedCourse.milestones.single.proofs, ['✅ 16.09 Сделать фичу #код']);

      final task = PomoTask(
        id: 't1',
        description: 'Задача под веху',
        category: 'код',
        durationMinutes: 25,
        week: true,
        milestoneId: 'm1',
      );
      await r.saveTasks(TasksFile(todo: [task], planner: const []));

      final loadedTasks = (await r.load()).getOrElse((f) => fail(f.message));
      expect(loadedTasks.todo.single.milestoneId, 'm1');
    });
  });
}
