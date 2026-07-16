import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/failure.dart';
import '../domain/entities/app_settings.dart';
import '../domain/entities/pomo_session.dart';
import '../domain/entities/pomo_task.dart';
import '../domain/entities/sprint.dart';
import '../domain/repositories.dart';
import 'markdown_codec.dart';

/// Доступ к папке хранилища. Корень меняется из настроек на лету.
class VaultStore {
  VaultStore(this.root);

  String root;

  static const tasksFileName = 'Задачи.md';
  static const journalDirName = 'Журнал';
  static const sprintsDirName = 'Спринты';

  File tasksFile() => File('$root${Platform.pathSeparator}$tasksFileName');

  File journalFile(DateTime d) => File(
    '$root${Platform.pathSeparator}$journalDirName'
    '${Platform.pathSeparator}${d.year}-${two(d.month)}'
    '${Platform.pathSeparator}${dateKey(d)}.md',
  );

  Directory sprintsDir() =>
      Directory('$root${Platform.pathSeparator}$sprintsDirName');

  File sprintFile(String id) =>
      File('${sprintsDir().path}${Platform.pathSeparator}$id.md');

  Future<String?> read(File file) async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> write(File file, String content) async {
    await file.parent.create(recursive: true);
    // Атомарно: temp + rename, чтобы Obsidian/Drive не видели полфайла.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
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

class TaskRepositoryImpl implements TaskRepository {
  TaskRepositoryImpl(this._store);

  final VaultStore _store;

  @override
  Future<Either<Failure, TasksFile>> load() {
    return _guard(() async {
      final content = await _store.read(_store.tasksFile());
      if (content == null) return const TasksFile(todo: [], planner: []);
      return parseTasksFile(content);
    });
  }

  @override
  Future<Either<Failure, Unit>> save(TasksFile file) {
    return _guard(() async {
      await _store.write(_store.tasksFile(), serializeTasksFile(file));
      return unit;
    });
  }
}

class JournalRepositoryImpl implements JournalRepository {
  JournalRepositoryImpl(this._store);

  final VaultStore _store;

  Future<DayLog> _day(DateTime date, int dailyGoal) async {
    final normalized = DateTime(date.year, date.month, date.day);
    final content = await _store.read(_store.journalFile(normalized));
    if (content == null) {
      return DayLog(date: normalized, goal: dailyGoal, sessions: const []);
    }
    return parseDayLog(content, normalized, dailyGoal);
  }

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int dailyGoal) {
    return _guard(() => _day(date, dailyGoal));
  }

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) {
    return _guard(() async {
      await _store.write(_store.journalFile(log.date), serializeDayLog(log));
      return unit;
    });
  }

  @override
  Future<Either<Failure, Unit>> addSession(PomoSession session, int dailyGoal) {
    return _guard(() async {
      // День длится с 05:00 до 05:00 — помидор в 00:30 идёт во вчерашний файл.
      final log = await _day(logicalDate(session.start), dailyGoal);
      // copyWith — иначе потеряются заметки «на чём встал».
      final updated = log.copyWith(
        goal: dailyGoal,
        sessions: [...log.sessions, session],
      );
      await _store.write(
        _store.journalFile(log.date),
        serializeDayLog(updated),
      );
      return unit;
    });
  }

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int dailyGoal,
  ) {
    return _guard(() async {
      final result = <DayLog>[];
      var cursor = DateTime(from.year, from.month, from.day);
      final last = DateTime(to.year, to.month, to.day);
      while (!cursor.isAfter(last)) {
        result.add(await _day(cursor, dailyGoal));
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }
      return result;
    });
  }
}

class SprintRepositoryImpl implements SprintRepository {
  SprintRepositoryImpl(this._store);

  final VaultStore _store;

  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int defaultGoal) {
    return _guard(() async {
      final id = sprintId(now);
      final monday = mondayOf(now);
      final content = await _store.read(_store.sprintFile(id));
      if (content == null) {
        return Sprint(id: id, start: monday, goal: defaultGoal);
      }
      return parseSprint(content, id, monday, defaultGoal);
    });
  }

  @override
  Future<Either<Failure, Unit>> save(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks = const [],
  }) {
    return _guard(() async {
      final file = _store.sprintFile(sprint.id);
      final content = serializeSprint(sprint, fact, weekTasks: weekTasks);
      // Не переписываем без изменений: меньше churn для Drive-синка
      // и меньше шансов затереть ручные правки.
      if (await _store.read(file) == content) return unit;
      await _store.write(file, content);
      return unit;
    });
  }

  @override
  Future<Either<Failure, List<SprintSummary>>> history() {
    return _guard(() async {
      final dir = _store.sprintsDir();
      if (!await dir.exists()) return const <SprintSummary>[];
      final summaries = <SprintSummary>[];
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final summary = parseSprintSummary(await entry.readAsString());
        if (summary != null) summaries.add(summary);
      }
      summaries.sort((a, b) => b.id.compareTo(a.id));
      return summaries;
    });
  }
}

class SettingsRepositoryImpl implements SettingsRepository {
  File? _file;

  Future<File> _settingsFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}settings.json');
    _file = file;
    return file;
  }

  static String defaultStoragePath() {
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      final vault = Directory(
        '$profile${Platform.pathSeparator}Мой диск'
        '${Platform.pathSeparator}Obsidian',
      );
      if (vault.existsSync()) {
        return '${vault.path}${Platform.pathSeparator}Помодоро';
      }
      return '$profile${Platform.pathSeparator}Documents'
          '${Platform.pathSeparator}Помодоро';
    }
    return 'Помодоро';
  }

  @override
  Future<Either<Failure, AppSettings>> load() async {
    try {
      final file = await _settingsFile();
      final fallback = defaultStoragePath();
      if (!await file.exists()) {
        return Either.right(
          AppSettings.fromJson(const {}, fallbackPath: fallback),
        );
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) {
        return Either.right(
          AppSettings.fromJson(const {}, fallbackPath: fallback),
        );
      }
      return Either.right(AppSettings.fromJson(json, fallbackPath: fallback));
    } on FileSystemException catch (e) {
      return Either.left(
        StorageFailure('Не удалось прочитать настройки: ${e.message}'),
      );
    } on FormatException {
      // Битый JSON — стартуем с настроек по умолчанию, не блокируя запуск.
      return Either.right(
        AppSettings.fromJson(const {}, fallbackPath: defaultStoragePath()),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> save(AppSettings settings) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
      return Either.right(unit);
    } on FileSystemException catch (e) {
      return Either.left(
        StorageFailure('Не удалось сохранить настройки: ${e.message}'),
      );
    }
  }
}
