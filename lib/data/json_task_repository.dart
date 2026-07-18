import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/failure.dart';
import '../domain/entities/pomo_task.dart';
import '../domain/repositories.dart';
import 'markdown_codec.dart';
import 'vault_repositories.dart';

/// Стабильный id задачи: время + случайный хвост. Сортируемый по времени
/// создания, генерится оффлайн, коллизии практически исключены.
String newTaskId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = Random().nextInt(0x7FFFFFFF).toRadixString(36);
  return '$time-$rand';
}

/// Хранилище задач — tasks.json в AppData: задачи больше не зависят от валта.
/// Валт получает одностороннее зеркало «Задачи.md» (только просмотр) и
/// отдаёт задачи один раз при миграции. Захват из валта — [InboxImporter].
class JsonTaskRepository implements TaskRepository {
  JsonTaskRepository(
    this._store, {
    required this.mirrorEnabled,
    Future<String> Function()? dirProvider,
  }) : _dirProvider =
           dirProvider ??
           (() async => (await getApplicationSupportDirectory()).path);

  final VaultStore _store;
  final bool Function() mirrorEnabled;
  final Future<String> Function() _dirProvider;
  File? _file;

  static const _mirrorNote =
      '<!-- Зеркало Помодоро Трекера: правки здесь не читаются. '
      'Захват задач — файл «Входящие.md». -->\n';

  Future<File> _jsonFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final file = File(
      '${await _dirProvider()}${Platform.pathSeparator}tasks.json',
    );
    _file = file;
    return file;
  }

  @override
  Future<Either<Failure, TasksFile>> load() {
    return _guard(() async {
      final file = await _jsonFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, dynamic>) {
          return const TasksFile(todo: [], planner: []);
        }
        return TasksFile(
          todo: _tasks(json['todo']),
          planner: _tasks(json['planner']),
        );
      }
      // Первый запуск: единожды мигрируем задачи из валта (Задачи.md).
      final content = await _store.read(_store.tasksFile());
      final migrated = _withIds(
        content == null
            ? const TasksFile(todo: [], planner: [])
            : parseTasksFile(content),
      );
      await _writeJson(file, migrated);
      return migrated;
    });
  }

  @override
  Future<Either<Failure, Unit>> save(TasksFile file) {
    return _guard(() async {
      final ready = _withIds(file);
      await _writeJson(await _jsonFile(), ready);
      await _mirror(ready);
      return unit;
    });
  }

  /// Выдать id новым задачам и развести дубликаты (после «Разбить» копия
  /// делит id с оригиналом). В памяти кубита задачи остаются со старыми id —
  /// диск всегда консистентен, память догоняет при следующем load().
  TasksFile _withIds(TasksFile file) {
    final seen = <String>{};
    PomoTask fix(PomoTask t) {
      final id = t.id;
      if (id != null && seen.add(id)) return t;
      final fresh = newTaskId();
      seen.add(fresh);
      return t.copyWith(id: fresh);
    }

    return TasksFile(
      todo: [for (final t in file.todo) fix(t)],
      planner: [for (final t in file.planner) fix(t)],
    );
  }

  Future<void> _writeJson(File file, TasksFile data) async {
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent(' ').convert({
      'schema': 1,
      'todo': [for (final t in data.todo) _toJson(t)],
      'planner': [for (final t in data.planner) _toJson(t)],
    });
    // Атомарно: temp + rename — как VaultStore.write.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }

  /// Одностороннее зеркало в валт. Валт недоступен — молча пропускаем:
  /// задачи от него больше не зависят.
  Future<void> _mirror(TasksFile data) async {
    if (!mirrorEnabled()) return;
    try {
      final file = _store.tasksFile();
      final content = _mirrorNote + serializeTasksFile(data);
      // Без изменений не переписываем — меньше churn для Drive/Obsidian.
      if (await _store.read(file) == content) return;
      await _store.write(file, content);
    } on FileSystemException {
      // Намеренно молча.
    }
  }

  Map<String, dynamic> _toJson(PomoTask t) => {
    'id': t.id,
    'desc': t.description,
    'cat': t.category,
    'min': t.durationMinutes,
    if (t.due != null) 'due': dateKey(t.due!),
    if (t.frog) 'frog': true,
    if (t.week) 'week': true,
  };

  List<PomoTask> _tasks(Object? raw) => [
    if (raw is List)
      for (final e in raw.whereType<Map<String, dynamic>>()) _fromJson(e),
  ];

  PomoTask _fromJson(Map<String, dynamic> j) {
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
