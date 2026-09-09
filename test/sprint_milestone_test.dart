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

/// Фейковый репозиторий спринтов в памяти, сохраняющий состояние для проверок.
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

/// Фейковый репозиторий направлений и вех в памяти.
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

Future<ScreenHarness> _pumpSprintScreen(
  WidgetTester tester, {
  required _MemSprints sprintRepo,
  required _MemCourse courseRepo,
}) async {
  tester.view
    ..physicalSize = const Size(600, 1000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final settings = SettingsCubit(
    FakeSettings(),
    initial: AppSettings.fromJson(const {}, fallbackPath: '.'),
    onStoragePathChanged: (_) {},
  );
  await settings.load();
  AppSettings current() => settings.state.settings;

  final journalRepo = FakeJournal();
  final tasks = TasksCubit(FakeTasks(), journalRepo, current, NotifyService());
  await tasks.load();

  final journal = JournalCubit(
    journalRepo,
    current,
    NotifyService(),
    onDayChanged: () async {},
  );
  await journal.refresh();

  final sprint = SprintCubit(
    sprintRepo,
    journalRepo,
    () => current().sprintGoal,
    () => current().dailyGoal,
    tasks.weekTasks,
  );
  await sprint.refresh();

  final stats = StatsCubit(journalRepo, () => current().dailyGoal);
  await stats.refresh();

  final timer = TimerCubit(
    settings: current,
    sound: SoundService(),
    notify: NotifyService(),
    store: FakeTimerStore(),
    hasTodos: () => true,
    onPomodoroComplete: (_) async {},
  );

  final directions = DirectionsCubit(courseRepo, journalRepo);
  await directions.refresh();

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: settings),
          BlocProvider.value(value: tasks),
          BlocProvider.value(value: journal),
          BlocProvider.value(value: sprint),
          BlocProvider.value(value: stats),
          BlocProvider.value(value: timer),
          BlocProvider.value(value: directions),
        ],
        child: const Scaffold(body: SprintScreen()),
      ),
    ),
  );
  await tester.pump();

  return ScreenHarness(() async {
    await tester.pumpWidget(const SizedBox());
    await tasks.close();
    await journal.close();
    await sprint.close();
    await stats.close();
    await timer.close();
    await directions.close();
    await settings.close();
  });
}

void main() {
  testWidgets(
      'закрытие вехи со спринт-экрана: веха помечается closed, sprint.milestoneId переходит на следующую открытую',
      (tester) async {
    final sprintRepo = _MemSprints(
      Sprint(
        id: '2026-W30',
        start: DateTime(2026, 7, 20),
        goal: 40,
        milestoneId: 'm1',
      ),
    );

    final courseRepo = _MemCourse(
      (
        directions: [
          const Direction(
            id: 'd1',
            name: 'Продукт',
            categories: ['prod'],
          ),
        ],
        milestones: [
          const Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Запустить MVP',
            order: 0,
          ),
          const Milestone(
            id: 'm2',
            directionId: 'd1',
            title: 'Привлечь 10 клиентов',
            order: 1,
          ),
        ],
      ),
    );

    final harness = await _pumpSprintScreen(
      tester,
      sprintRepo: sprintRepo,
      courseRepo: courseRepo,
    );

    // До нажатия: отображается первая веха и кнопка закрытия
    expect(find.text('Запустить MVP'), findsOneWidget);
    expect(find.text('Продукт · веха 1 из 2'), findsOneWidget);
    expect(find.text(S.courseCloseMilestone), findsOneWidget);

    // Закрываем веху
    await tester.tap(find.text(S.courseCloseMilestone));
    await tester.pumpAndSettle();

    // Проверяем: веха m1 закрыта, sprint.milestoneId указывает на m2
    expect(sprintRepo.sprint.milestoneId, 'm2');
    final m1Updated =
        courseRepo.course.milestones.firstWhere((m) => m.id == 'm1');
    expect(m1Updated.done, isTrue);
    expect(m1Updated.doneSprint, '2026-W30');

    // Экран обновился и показывает следующую веху
    expect(find.text('Привлечь 10 клиентов'), findsOneWidget);
    expect(find.text('Продукт · веха 2 из 2'), findsOneWidget);

    await harness.dispose();
  });

  testWidgets(
      'закрытие последней открытой вехи: sprint.milestoneId очищается, статус лестницы «пройдена»',
      (tester) async {
    final sprintRepo = _MemSprints(
      Sprint(
        id: '2026-W30',
        start: DateTime(2026, 7, 20),
        goal: 40,
        milestoneId: 'm1',
      ),
    );

    final courseRepo = _MemCourse(
      (
        directions: [
          const Direction(
            id: 'd1',
            name: 'Продукт',
            categories: ['prod'],
          ),
        ],
        milestones: [
          const Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Финальная веха',
            order: 0,
          ),
        ],
      ),
    );

    final harness = await _pumpSprintScreen(
      tester,
      sprintRepo: sprintRepo,
      courseRepo: courseRepo,
    );

    expect(find.text('Финальная веха'), findsOneWidget);
    expect(find.text(S.courseCloseMilestone), findsOneWidget);

    // Закрываем единственную (последнюю) веху
    await tester.tap(find.text(S.courseCloseMilestone));
    await tester.pumpAndSettle();

    // milestoneId очищен, веха m1 помечена закрытой
    expect(sprintRepo.sprint.milestoneId, isEmpty);
    final m1Updated =
        courseRepo.course.milestones.firstWhere((m) => m.id == 'm1');
    expect(m1Updated.done, isTrue);

    // Появляется сообщение о том, что лестница пройдена
    expect(find.text('Продукт: ${S.courseLadderPassed}'), findsOneWidget);

    await harness.dispose();
  });

  testWidgets(
      'выбор вехи из лестницы через диалог привязывает sprint.milestoneId',
      (tester) async {
    final sprintRepo = _MemSprints(
      Sprint(
        id: '2026-W30',
        start: DateTime(2026, 7, 20),
        goal: 40,
        milestoneId: '',
      ),
    );

    final courseRepo = _MemCourse(
      (
        directions: [
          const Direction(
            id: 'd1',
            name: 'Продукт',
            categories: ['prod'],
          ),
        ],
        milestones: [
          const Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Первая веха',
            order: 0,
          ),
        ],
      ),
    );

    final harness = await _pumpSprintScreen(
      tester,
      sprintRepo: sprintRepo,
      courseRepo: courseRepo,
    );

    // Открываем диалог выбора вехи. Ищем по тултипу, а не по иконке:
    // карандашей на экране два — у цели недели и у вехи.
    await tester.tap(find.byTooltip(S.pickMilestone));
    await tester.pumpAndSettle();

    expect(find.text(S.pickMilestone), findsOneWidget);
    expect(find.text('Первая веха'), findsOneWidget);

    // Выбираем веху из диалога
    await tester.tap(find.text('Первая веха'));
    await tester.pumpAndSettle();

    // Диалог закрылся, sprint.milestoneId стал m1
    expect(sprintRepo.sprint.milestoneId, 'm1');
    expect(find.text('Первая веха'), findsOneWidget);
    expect(find.text(S.courseCloseMilestone), findsOneWidget);

    await harness.dispose();
  });
}
