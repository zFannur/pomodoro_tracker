import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/json_data_repository.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/services/frog_rollover.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';

void main() {
  late Directory temp;
  late JsonDataRepository repo;
  late TasksCubit tasks;
  late InsightCubit insights;
  AppSettings settings() => AppSettings.fromJson(const {}, fallbackPath: '.');
  const frog = PomoTask(
    id: 'frog',
    description: 'лягушка',
    category: 'x',
    durationMinutes: 50,
    frog: true,
    deferrals: 2,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pomo_p06_');
    repo = JsonDataRepository(
      VaultStore('${temp.path}/vault'),
      mirrorEnabled: () => false,
      dirProvider: () async => temp.path,
    );
    await repo.saveTasks(const TasksFile(todo: [frog], planner: []));
    tasks = TasksCubit(repo, repo, settings, NotifyService());
    insights = InsightCubit(repo, repo, repo, settings);
    await tasks.load();
  });
  tearDown(() async {
    await tasks.close();
    await insights.close();
    await temp.delete(recursive: true);
  });

  Future<void> rollover(String? day) =>
      withClock(Clock.fixed(DateTime(2026, 11, 9, 8)), () async {
        expect(
          await recordUntouchedFrog(
            previousDay: day,
            tasks: tasks,
            journal: repo,
            insights: insights,
            dailyGoal: 8,
          ),
          isTrue,
        );
      });

  test(
    'после нескольких дней отсутствия — один сигнал за marks.day в 23:59',
    () async {
      await rollover('2026-11-04');
      expect(tasks.state.todo.single.deferrals, 3);
      final log = (await repo.day(
        DateTime(2026, 11, 4),
        8,
      )).getOrElse((_) => throw StateError('day'));
      final e = log.episodes.single;
      expect(e.source, EpisodeSource.frog);
      expect(e.at, DateTime(2026, 11, 4, 23, 59));
      expect(logicalDate(e.at), log.date);
      expect(e.taskId, 'frog');
      expect(e.task, frog.description);
      expect(insights.state.lastDeferral, isNull);
      // Повторная проверка до обновления отметок не дублирует эпизод.
      await rollover('2026-11-04');
      expect(tasks.state.todo.single.deferrals, 3);
      await tasks.clearFrogs();
      expect(tasks.state.todo.single.frog, isFalse);
    },
  );

  test('сессия именно в marks.day по id лягушки подавляет сигнал', () async {
    await repo.addSession(
      PomoSession(
        id: 's',
        start: DateTime(2026, 11, 5, 0, 30),
        minutes: 10,
        category: 'x',
        task: 'старое описание',
        taskId: 'frog',
      ),
      8,
    );
    await rollover('2026-11-04');
    expect(tasks.state.todo.single.deferrals, 2);
    expect(insights.state.days.expand((d) => d.episodes), isEmpty);
  });

  test('чужая задача и сессия другого дня не подавляют сигнал', () async {
    for (final (id, start, taskId) in [
      ('other', DateTime(2026, 11, 4, 10), 'other'),
      ('next', DateTime(2026, 11, 5, 10), 'frog'),
    ]) {
      await repo.addSession(
        PomoSession(
          id: id,
          start: start,
          minutes: 25,
          category: 'x',
          task: 'лягушка',
          taskId: taskId,
        ),
        8,
      );
    }
    await rollover('2026-11-04');
    expect(tasks.state.todo.single.deferrals, 3);
  });

  test('первый запуск marks.day null — без сигнала', () async {
    await rollover(null);
    expect(tasks.state.todo.single.deferrals, 2);
    expect(insights.state.days, isEmpty);
  });

  test('обычная задача пережила ночь — не перенос', () async {
    await tasks.clearFrogs();
    await rollover('2026-11-04');
    expect(tasks.state.todo.single.deferrals, 2);
    expect(insights.state.days, isEmpty);
  });
}
