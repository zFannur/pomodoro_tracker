import '../domain/entities/episode.dart';
import '../domain/repositories.dart';
import '../presentation/cubits/insight_cubit.dart';
import '../presentation/cubits/tasks_cubit.dart';

/// Проверяем последний обработанный день, а не все дни отсутствия приложения.
/// false оставляет отметку rollover прежней при ошибке чтения/записи.
Future<bool> recordUntouchedFrog({
  required String? previousDay,
  required TasksCubit tasks,
  required JournalRepository journal,
  required InsightCubit insights,
  required int dailyGoal,
}) async {
  if (previousDay == null) return true;
  final day = DateTime.tryParse(previousDay);
  final frog = tasks.state.todo.where((task) => task.frog).firstOrNull;
  final id = frog?.id;
  if (day == null || id == null || id.isEmpty) return true;
  final result = await journal.day(day, dailyGoal);
  final log = result.fold((_) => null, (value) => value);
  if (log == null) return false;
  if (log.sessions.any((session) => session.taskId == id) ||
      log.episodes.any(
        (e) => e.source == EpisodeSource.frog && e.taskId == id,
      )) {
    return true;
  }
  final updated = await tasks.bumpDeferral(id);
  if (updated == null) return false;
  await insights.addEpisode(
    source: EpisodeSource.frog,
    task: updated,
    at: DateTime(day.year, day.month, day.day, 23, 59),
  );
  return insights.state.status != InsightStatus.failure;
}
