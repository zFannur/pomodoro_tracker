import 'package:fpdart/fpdart.dart';

import '../core/failure.dart';
import 'entities/app_settings.dart';
import 'entities/pomo_session.dart';
import 'entities/pomo_task.dart';
import 'entities/sprint.dart';

/// Задачи: TODO + планировщик (файл Задачи.md).
abstract interface class TaskRepository {
  Future<Either<Failure, TasksFile>> load();

  Future<Either<Failure, Unit>> save(TasksFile file);
}

/// Журнал помидоров по дням (Журнал/YYYY-MM/YYYY-MM-DD.md).
/// Дата дня — логическая (день длится с 05:00 до 05:00).
abstract interface class JournalRepository {
  Future<Either<Failure, Unit>> addSession(PomoSession session, int dailyGoal);

  Future<Either<Failure, Unit>> saveDay(DayLog log);

  Future<Either<Failure, DayLog>> day(DateTime date, int dailyGoal);

  /// Журналы диапазона дат включительно; отсутствующие дни — пустые DayLog.
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int dailyGoal,
  );
}

/// Спринты (Спринты/YYYY-Wnn.md).
abstract interface class SprintRepository {
  Future<Either<Failure, Sprint>> current(DateTime now, int defaultGoal);

  Future<Either<Failure, Unit>> save(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks,
  });

  Future<Either<Failure, List<SprintSummary>>> history();
}

/// Настройки приложения (JSON в AppData).
abstract interface class SettingsRepository {
  Future<Either<Failure, AppSettings>> load();

  Future<Either<Failure, Unit>> save(AppSettings settings);
}
