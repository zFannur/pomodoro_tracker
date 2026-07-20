import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/json_data_repository.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

void main() {
  late Directory vaultDir;
  late Directory dataDir;
  late VaultStore store;
  var mirror = true;

  JsonDataRepository repo() => JsonDataRepository(
    store,
    mirrorEnabled: () => mirror,
    dirProvider: () async => dataDir.path,
  );

  setUp(() {
    vaultDir = Directory.systemTemp.createTempSync('pomo_vault');
    dataDir = Directory.systemTemp.createTempSync('pomo_data');
    store = VaultStore(vaultDir.path);
    mirror = true;
  });

  tearDown(() {
    vaultDir.deleteSync(recursive: true);
    dataDir.deleteSync(recursive: true);
  });

  PomoTask t(
    String d, {
    String? id,
    DateTime? due,
    bool frog = false,
    bool week = false,
  }) => PomoTask(
    description: d,
    category: 'кат',
    durationMinutes: 25,
    id: id,
    due: due,
    frog: frog,
    week: week,
  );

  PomoSession s(String id, DateTime start) => PomoSession(
    id: id,
    start: start,
    minutes: 25,
    category: 'кат',
    task: 'задача $id',
  );

  File dataFile() => File('${dataDir.path}/data.json');
  Map<String, dynamic> readDoc() =>
      jsonDecode(dataFile().readAsStringSync()) as Map<String, dynamic>;

  test('миграция: задачи из tasks.json, журнал и спринты из валта', () async {
    File('${dataDir.path}/tasks.json').writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'todo': [
          {'id': 'x1', 'desc': 'первая', 'cat': 'кат', 'min': 25, 'frog': true},
        ],
        'planner': <Object>[],
      }),
    );
    final day = DateTime(2026, 7, 16);
    await store.write(
      store.journalFile(day),
      serializeDayLog(
        DayLog(date: day, goal: 8, sessions: [s('m1', DateTime(2026, 7, 16, 9))]),
      ),
    );
    await store.write(
      store.sprintFile('2026-W29'),
      serializeSprint(
        Sprint(
          id: '2026-W29',
          start: DateTime(2026, 7, 13),
          goal: 40,
          milestone: 'веха',
        ),
        const [],
      ),
    );

    final r = repo();
    final tasks = (await r.load()).getOrElse((f) => fail(f.message));
    expect(tasks.todo.single.description, 'первая');
    expect(tasks.todo.single.frog, isTrue);

    final loaded = (await r.day(day, 8)).getOrElse((f) => fail(f.message));
    expect(loaded.sessions.single.task, 'задача m1');

    final sprint = (await r.current(DateTime(2026, 7, 15), 40))
        .getOrElse((f) => fail(f.message));
    expect(sprint.milestone, 'веха');
    expect(dataFile().existsSync(), isTrue);
  });

  test('миграция журнала повторяема: id детерминированы', () async {
    // Два устройства мигрируют одну историю независимо; при случайных id
    // первое же слияние удвоило бы весь журнал.
    final day = DateTime(2026, 7, 16);
    final content = serializeDayLog(
      DayLog(
        date: day,
        goal: 8,
        sessions: [s('a', DateTime(2026, 7, 16, 9)), s('b', DateTime(2026, 7, 16, 9))],
      ),
    );
    await store.write(store.journalFile(day), content);

    final first = (await repo().day(day, 8)).getOrElse((f) => fail(f.message));
    dataFile().deleteSync();
    final second = (await repo().day(day, 8)).getOrElse((f) => fail(f.message));
    expect(
      first.sessions.map((x) => x.id).toList(),
      second.sessions.map((x) => x.id).toList(),
    );
    // Две записи одной минуты получают разные id.
    expect(first.sessions.map((x) => x.id).toSet(), hasLength(2));
  });

  test('round-trip задач: поля сохраняются, id выдаются и не дублируются',
      () async {
    final r = repo();
    await r.saveTasks(
      TasksFile(
        todo: [t('a', frog: true), t('b', week: true, id: 'same'), t('c', id: 'same')],
        planner: [t('d', due: DateTime(2026, 8, 1))],
      ),
    );
    final loaded = (await repo().load()).getOrElse((f) => fail(f.message));
    expect(loaded.todo.map((x) => x.description), ['a', 'b', 'c']);
    expect(loaded.todo[1].week, isTrue);
    expect(loaded.planner.single.due, DateTime(2026, 8, 1));
    final ids = [...loaded.todo, ...loaded.planner].map((x) => x.id!).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('round-trip журнала: помидор переживает перезагрузку', () async {
    final r = repo();
    final start = DateTime(2026, 7, 20, 14, 32);
    await r.addSession(
      PomoSession(
        id: 'p1',
        start: start,
        minutes: 25,
        category: 'код',
        task: 'экран',
        delayMinutes: 3,
        interruptions: 1,
        frog: true,
      ),
      8,
    );
    final day = (await repo().day(DateTime(2026, 7, 20), 8))
        .getOrElse((f) => fail(f.message));
    final session = day.sessions.single;
    expect(session.id, 'p1');
    expect(session.start, start);
    expect(session.delayMinutes, 3);
    expect(session.interruptions, 1);
    expect(session.frog, isTrue);
  });

  test('помидор после полуночи попадает во вчерашний логический день',
      () async {
    final r = repo();
    // 00:30 21-го — это ещё день 20-го (сутки с 05:00).
    await r.addSession(s('ночь', DateTime(2026, 7, 21, 0, 30)), 8);
    final day = (await r.day(DateTime(2026, 7, 20), 8))
        .getOrElse((f) => fail(f.message));
    expect(day.sessions.single.id, 'ночь');
    expect(day.sessions.single.start, DateTime(2026, 7, 21, 0, 30));
  });

  test('удаление задачи ставит надгробие, возврат — снимает', () async {
    final r = repo();
    await r.saveTasks(TasksFile(todo: [t('a', id: 'a1'), t('b', id: 'b1')], planner: []));
    expect(readDoc()['graves'], isEmpty);

    await r.saveTasks(TasksFile(todo: [t('a', id: 'a1')], planner: []));
    expect((readDoc()['graves'] as Map).keys, ['b1']);

    // Восстановление из корзины возвращает ту же запись — надгробие лишнее.
    await r.saveTasks(
      TasksFile(todo: [t('a', id: 'a1'), t('b', id: 'b1')], planner: []),
    );
    expect(readDoc()['graves'], isEmpty);
  });

  test('удаление записи журнала тоже хоронится', () async {
    final r = repo();
    await r.addSession(s('p1', DateTime(2026, 7, 20, 9)), 8);
    await r.addSession(s('p2', DateTime(2026, 7, 20, 10)), 8);
    final day = (await r.day(DateTime(2026, 7, 20), 8))
        .getOrElse((f) => fail(f.message));
    await r.saveDay(
      day.copyWith(sessions: day.sessions.where((x) => x.id == 'p1').toList()),
    );
    expect((readDoc()['graves'] as Map).keys, ['p2']);
  });

  test('range синтезирует пустые дни — на них завязаны серия и темп',
      () async {
    final r = repo();
    await r.addSession(s('p1', DateTime(2026, 7, 20, 9)), 8);
    final days = (await r.range(DateTime(2026, 7, 18), DateTime(2026, 7, 20), 8))
        .getOrElse((f) => fail(f.message));
    expect(days, hasLength(3));
    expect(days.first.count, 0);
    expect(days.last.count, 1);
  });

  test('сохранение спринта без изменений не дёргает синк', () async {
    final r = repo();
    final sprint = Sprint(
      id: '2026-W30',
      start: DateTime(2026, 7, 20),
      goal: 40,
      milestone: 'веха',
    );
    await r.saveSprint(sprint, const []);
    var saves = 0;
    r.onSaved = () => saves++;
    // refresh() спринта зовётся после каждого помидора: без этой проверки
    // каждый помидор отправлял бы файл в Drive.
    await r.saveSprint(sprint, const []);
    expect(saves, 0);
    await r.saveSprint(sprint.copyWith(goal: 50), const []);
    expect(saves, 1);
  });

  test('applyRemote заменяет документ и не зовёт onSaved', () async {
    final r = repo();
    await r.saveTasks(TasksFile(todo: [t('локальная', id: 'l1')], planner: []));
    var saves = 0;
    r.onSaved = () => saves++;
    await r.applyRemote(
      jsonEncode({
        'schema': 2,
        'todo': [
          {'id': 'r1', 'desc': 'удалённая', 'cat': 'кат', 'min': 25},
        ],
        'planner': <Object>[],
        'days': <String, Object>{},
        'sprints': <String, Object>{},
        'graves': <String, Object>{},
      }),
    );
    final loaded = (await r.load()).getOrElse((f) => fail(f.message));
    expect(loaded.todo.single.description, 'удалённая');
    // Пришедшее снаружи не надо отправлять обратно.
    expect(saves, 0);
  });

  test('applyRemote не даёт следующей записи похоронить приехавшее', () async {
    final r = repo();
    await r.saveTasks(TasksFile(todo: [t('своя', id: 'l1')], planner: []));
    await r.applyRemote(
      jsonEncode({
        'schema': 2,
        'todo': [
          {'id': 'l1', 'desc': 'своя', 'cat': 'кат', 'min': 25},
          {'id': 'r1', 'desc': 'чужая', 'cat': 'кат', 'min': 25},
        ],
        'planner': <Object>[],
        'days': <String, Object>{},
        'sprints': <String, Object>{},
        'graves': <String, Object>{},
      }),
    );
    // Правка после прилёта: документ в памяти обновлён, поэтому чужая задача
    // считается существующей, а не «исчезнувшей».
    final loaded = (await r.load()).getOrElse((f) => fail(f.message));
    await r.saveTasks(TasksFile(todo: loaded.todo, planner: const []));
    expect(readDoc()['graves'], isEmpty);
  });

  test('зеркало: markdown пишется с пометкой; выключено — не пишется',
      () async {
    mirror = false;
    final r = repo();
    await r.saveTasks(TasksFile(todo: [t('a')], planner: []));
    await r.addSession(s('p1', DateTime(2026, 7, 20, 9)), 8);
    expect(store.tasksFile().existsSync(), isFalse);
    expect(store.journalFile(DateTime(2026, 7, 20)).existsSync(), isFalse);

    mirror = true;
    await r.saveTasks(TasksFile(todo: [t('a')], planner: []));
    await r.addSession(s('p2', DateTime(2026, 7, 20, 10)), 8);
    expect(store.tasksFile().readAsStringSync(), contains('<!--'));
    final journal = store.journalFile(DateTime(2026, 7, 20)).readAsStringSync();
    expect(journal, contains('<!--'));
    expect(journal, contains('задача p2'));
  });

  group('InboxImporter', () {
    test('нет файла — создаёт шаблон и возвращает пусто', () async {
      final imp = InboxImporter(store);
      expect(await imp.drain(), isEmpty);
      final content = File('${vaultDir.path}/Входящие.md').readAsStringSync();
      expect(content, contains('# Входящие'));
    });

    test('забирает строки, режет маркеры, не трогает шапку, чистит файл',
        () async {
      final imp = InboxImporter(store);
      final file = File('${vaultDir.path}/Входящие.md');
      file.writeAsStringSync(
        '# Входящие\n'
        '<!-- подсказка -->\n'
        '- [ ] купить хлеб ~1\n'
        '- #личное позвонить маме\n'
        '* звёздочный пункт\n'
        'просто строка\n'
        '- \n'
        '\n',
      );
      expect(await imp.drain(), [
        'купить хлеб ~1',
        '#личное позвонить маме',
        'звёздочный пункт',
        'просто строка',
      ]);
      expect(file.readAsStringSync(), InboxImporter.template);
      expect(await imp.drain(), isEmpty);
    });

    test('строка «#категория текст» — задача, а не заголовок', () async {
      final imp = InboxImporter(store);
      File('${vaultDir.path}/Входящие.md')
          .writeAsStringSync('#работа срочный фикс ~2\n');
      expect(await imp.drain(), ['#работа срочный фикс ~2']);
    });
  });
}
