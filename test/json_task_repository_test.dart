import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/json_task_repository.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';

void main() {
  late Directory vaultDir;
  late Directory dataDir;
  late VaultStore store;
  var mirror = true;

  JsonTaskRepository repo() => JsonTaskRepository(
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

  File jsonFile() => File('${dataDir.path}/tasks.json');
  File mirrorFile() => File('${vaultDir.path}/Задачи.md');

  test('миграция: первый load() забирает Задачи.md и создаёт tasks.json',
      () async {
    final legacy = TasksFile(
      todo: [t('первая', frog: true)],
      planner: [t('вторая', due: DateTime(2026, 7, 20))],
    );
    mirrorFile().writeAsStringSync(serializeTasksFile(legacy));

    final result = await repo().load();
    final file = result.getOrElse((f) => fail(f.message));
    expect(file.todo.single.description, 'первая');
    expect(file.todo.single.frog, isTrue);
    expect(file.todo.single.id, isNotNull);
    expect(file.planner.single.due, DateTime(2026, 7, 20));
    expect(jsonFile().existsSync(), isTrue);
  });

  test('round-trip: save → load сохраняет все поля и выдаёт id', () async {
    final data = TasksFile(
      todo: [t('a', frog: true), t('b', week: true)],
      planner: [t('c', due: DateTime(2026, 8, 1))],
    );
    await repo().save(data);

    final loaded = (await repo().load()).getOrElse((f) => fail(f.message));
    expect(loaded.todo.map((x) => x.description), ['a', 'b']);
    expect(loaded.todo.first.frog, isTrue);
    expect(loaded.todo.last.week, isTrue);
    expect(loaded.planner.single.due, DateTime(2026, 8, 1));
    final ids = [...loaded.todo, ...loaded.planner].map((x) => x.id).toList();
    expect(ids.every((id) => id != null && id.isNotEmpty), isTrue);
    expect(ids.toSet().length, ids.length);
  });

  test('дубликаты id (после «Разбить») разводятся при сохранении', () async {
    await repo().save(
      TasksFile(todo: [t('a', id: 'same'), t('b', id: 'same')], planner: []),
    );
    final loaded = (await repo().load()).getOrElse((f) => fail(f.message));
    expect(loaded.todo.first.id, 'same');
    expect(loaded.todo.last.id, isNot('same'));
  });

  test('зеркало: пишет Задачи.md с пометкой; выключено — не пишет', () async {
    mirror = false;
    await repo().save(TasksFile(todo: [t('a')], planner: []));
    expect(mirrorFile().existsSync(), isFalse);

    mirror = true;
    await repo().save(TasksFile(todo: [t('a')], planner: []));
    final content = mirrorFile().readAsStringSync();
    expect(content, contains('<!--'));
    expect(content, contains('a #кат'));
    // Комментарий не мешает обратному разбору (аварийный откат).
    expect(parseTasksFile(content).todo.single.description, 'a');
  });

  group('InboxImporter', () {
    test('нет файла — создаёт шаблон и возвращает пусто', () async {
      final imp = InboxImporter(store);
      expect(await imp.drain(), isEmpty);
      final content =
          File('${vaultDir.path}/Входящие.md').readAsStringSync();
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
      // Повторный дрейн шаблона — пусто и без перезаписи.
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
