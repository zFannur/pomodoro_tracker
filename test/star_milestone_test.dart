import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/journal_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/sprint_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/stats_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/sprint_screen.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';

import 'screen_fakes.dart';

class _MemTasks implements TaskRepository {
  _MemTasks(this.file);

  TasksFile file;

  @override
  Future<Either<Failure, TasksFile>> load() async => Either.right(file);

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile file) async {
    this.file = file;
    return Either.right(unit);
  }
}

class _MemSprints implements SprintRepository {
  _MemSprints(this.sprint);

  Sprint sprint;

  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int goal) async =>
      Either.right(sprint);

  @override
  Future<Either<Failure, Unit>> saveSprint(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks = const [],
  }) async {
    this.sprint = sprint;
    return Either.right(unit);
  }

  @override
  Future<Either<Failure, List<SprintSummary>>> history() async =>
      Either.right(const []);
}

class _MemCourse implements DirectionRepository {
  _MemCourse(this.course);

  Course course;

  @override
  Future<Either<Failure, Course>> loadCourse() async => Either.right(course);

  @override
  Future<Either<Failure, Unit>> saveCourse(Course course) async {
    this.course = course;
    return Either.right(unit);
  }
}

void main() {
  group('постановка и снятие ⭐ в TasksCubit', () {
    late _MemTasks tasksRepo;
    late FakeJournal journalRepo;
    late TasksCubit tasksCubit;
    String currentMilestone = 'm-current';

    setUp(() async {
      currentMilestone = 'm-current';
      tasksRepo = _MemTasks(
        const TasksFile(
          todo: [
            PomoTask(
              id: 't1',
              description: 'Задача в сегодня',
              category: 'код',
              durationMinutes: 25,
            ),
          ],
          planner: [
            PomoTask(
              id: 'p1',
              description: 'Задача в плане',
              category: 'код',
              durationMinutes: 25,
            ),
          ],
        ),
      );
      journalRepo = FakeJournal();
      tasksCubit = TasksCubit(
        tasksRepo,
        journalRepo,
        () => AppSettings.fromJson(const {}, fallbackPath: '.'),
        NotifyService(),
        () => currentMilestone,
      );
      await tasksCubit.load();
    });

    tearDown(() async {
      await tasksCubit.close();
    });

    test('постановка ⭐ проставляет milestoneId текущего спринта', () async {
      // Постановка ⭐ на задачу в TODO
      await tasksCubit.toggleWeek(0);
      expect(tasksCubit.state.todo.first.week, isTrue);
      expect(tasksCubit.state.todo.first.milestoneId, 'm-current');

      // Постановка ⭐ на задачу в Планировщике
      await tasksCubit.toggleWeek(0, inPlanner: true);
      expect(tasksCubit.state.planner.first.week, isTrue);
      expect(tasksCubit.state.planner.first.milestoneId, 'm-current');
    });

    test('снятие ⭐ очищает milestoneId', () async {
      // Сначала ставим ⭐
      await tasksCubit.toggleWeek(0);
      expect(tasksCubit.state.todo.first.week, isTrue);
      expect(tasksCubit.state.todo.first.milestoneId, 'm-current');

      // Снимаем ⭐
      await tasksCubit.toggleWeek(0);
      expect(tasksCubit.state.todo.first.week, isFalse);
      expect(tasksCubit.state.todo.first.milestoneId, isEmpty);

      // Аналогично для планировщика
      await tasksCubit.toggleWeek(0, inPlanner: true);
      expect(tasksCubit.state.planner.first.week, isTrue);
      expect(tasksCubit.state.planner.first.milestoneId, 'm-current');

      await tasksCubit.toggleWeek(0, inPlanner: true);
      expect(tasksCubit.state.planner.first.week, isFalse);
      expect(tasksCubit.state.planner.first.milestoneId, isEmpty);
    });

    test('clearWeekFlags очищает и флаг, и привязку', () async {
      await tasksCubit.toggleWeek(0);
      await tasksCubit.toggleWeek(0, inPlanner: true);

      expect(tasksCubit.state.todo.first.week, isTrue);
      expect(tasksCubit.state.todo.first.milestoneId, 'm-current');
      expect(tasksCubit.state.planner.first.week, isTrue);
      expect(tasksCubit.state.planner.first.milestoneId, 'm-current');

      await tasksCubit.clearWeekFlags();

      expect(tasksCubit.state.todo.first.week, isFalse);
      expect(tasksCubit.state.todo.first.milestoneId, isEmpty);
      expect(tasksCubit.state.planner.first.week, isFalse);
      expect(tasksCubit.state.planner.first.milestoneId, isEmpty);
    });

    test('закрытие ⭐-задачи кладёт строку и в Sprint.doneWeek, и в proofs вехи', () async {
      final sprintRepo = _MemSprints(
        Sprint(
          id: '2026-W37',
          start: DateTime(2026, 9, 7),
          goal: 40,
          milestoneId: 'm-current',
        ),
      );
      final courseRepo = _MemCourse(
        (
          directions: [
            const Direction(id: 'd1', name: 'Проект'),
          ],
          milestones: [
            const Milestone(
              id: 'm-current',
              directionId: 'd1',
              title: 'Ступень 1',
            ),
          ],
        ),
      );

      final sprintCubit = SprintCubit(
        sprintRepo,
        journalRepo,
        () => 40,
        () => 4,
        tasksCubit.weekTasks,
      );
      await sprintCubit.refresh();

      final directionsCubit = DirectionsCubit(courseRepo, journalRepo);
      await directionsCubit.refresh();

      // Проводка как в main.dart
      tasksCubit.onWeeklyClosed = (line, milestoneId) async {
        await sprintCubit.addDoneWeek(line);
        await directionsCubit.addProof(milestoneId, line);
      };

      // Ставим ⭐ на задачу
      await tasksCubit.toggleWeek(0);
      expect(tasksCubit.state.todo.first.week, isTrue);
      expect(tasksCubit.state.todo.first.milestoneId, 'm-current');

      // Закрываем задачу
      await tasksCubit.markDone(0, whole: true);

      // Проверяем doneWeek в спринте
      expect(sprintCubit.state.sprint?.doneWeek.length, 1);
      final closedLine = sprintCubit.state.sprint!.doneWeek.first;
      expect(closedLine, contains('Задача в сегодня #код'));

      // Проверяем proofs в вехе
      final m = directionsCubit.state.milestoneById('m-current');
      expect(m?.proofs.length, 1);
      expect(m?.proofs.first, closedLine);

      await sprintCubit.close();
      await directionsCubit.close();
    });
  });

  group('Экран «Спринт» — отображение счётчика и пометки вехи', () {
    testWidgets('счётчик в карточке вехи и точка у задачи текущей вехи', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 1000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final settings = SettingsCubit(
        FakeSettings(),
        initial: AppSettings.fromJson(const {}, fallbackPath: '.'),
        onStoragePathChanged: (_) {},
      );
      await settings.load();

      final journalRepo = FakeJournal();
      final sprintRepo = _MemSprints(
        Sprint(
          id: '2026-W37',
          start: DateTime(2026, 9, 7),
          goal: 40,
          milestoneId: 'm1',
        ),
      );

      final courseRepo = _MemCourse(
        (
          directions: [
            const Direction(id: 'd1', name: 'Продукт'),
          ],
          milestones: [
            const Milestone(
              id: 'm1',
              directionId: 'd1',
              title: 'Ступень 1',
              proofs: ['✅ 08.09 Закрытое дело #код'],
            ),
          ],
        ),
      );

      // Задача 1 привязана к текущей вехе m1
      // Задача 2 привязана к другой (старой) вехе m_old
      final tasksRepo = _MemTasks(
        const TasksFile(
          todo: [
            PomoTask(
              id: 't1',
              description: 'Задача под текущую веху',
              category: 'код',
              durationMinutes: 25,
              week: true,
              milestoneId: 'm1',
            ),
            PomoTask(
              id: 't2',
              description: 'Задача под старую веху',
              category: 'дизайн',
              durationMinutes: 25,
              week: true,
              milestoneId: 'm_old',
            ),
          ],
          planner: [],
        ),
      );

      final tasksCubit = TasksCubit(
        tasksRepo,
        journalRepo,
        () => settings.state.settings,
        NotifyService(),
        () => 'm1',
      );
      await tasksCubit.load();

      final sprintCubit = SprintCubit(
        sprintRepo,
        journalRepo,
        () => 40,
        () => 4,
        tasksCubit.weekTasks,
      );
      await sprintCubit.refresh();

      final directionsCubit = DirectionsCubit(courseRepo, journalRepo);
      await directionsCubit.refresh();

      final journalCubit = JournalCubit(
        journalRepo,
        () => settings.state.settings,
        NotifyService(),
        onDayChanged: () async {},
      );
      await journalCubit.refresh();

      final statsCubit = StatsCubit(journalRepo, () => 4);
      await statsCubit.refresh();

      final timerCubit = TimerCubit(
        settings: () => settings.state.settings,
        sound: SoundService(),
        notify: NotifyService(),
        store: FakeTimerStore(),
        hasTodos: () => true,
        onPomodoroComplete: (_) async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settings),
              BlocProvider.value(value: tasksCubit),
              BlocProvider.value(value: journalCubit),
              BlocProvider.value(value: sprintCubit),
              BlocProvider.value(value: statsCubit),
              BlocProvider.value(value: timerCubit),
              BlocProvider.value(value: directionsCubit),
            ],
            child: const Scaffold(body: SprintScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем строку счётчика вехи: 1 задача под m1, 1 доказательство
      // «⭐ 1 задача · закрыто 1»
      expect(
        find.text(S.milestoneProgressCounter(1, 1)),
        findsOneWidget,
      );

      // Проверяем тултип пометки: ровно 1 задача (t1) имеет тултип «двигает веху недели»
      expect(find.byTooltip(S.movesWeeklyMilestone), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tasksCubit.close();
      await journalCubit.close();
      await sprintCubit.close();
      await statsCubit.close();
      await timerCubit.close();
      await directionsCubit.close();
      await settings.close();
    });
  });
}
