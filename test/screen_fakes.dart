import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/data/timer_state_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/journal_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/sprint_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/stats_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';

/// Общие заглушки и сборка экрана для тестов раскладки.
///
/// Данные намеренно «неудобные»: длинные описания и длинные категории —
/// именно на них экраны и разъезжались на телефоне.

/// Описания, по которым тесты меряют доставшуюся тексту ширину.
const kLongTodo = 'настроить ci/cd для репо видеоаналитики';
const kLongPlanned = 'КВОРК 5 — YOLO / компьютерное зрение (ниша пустая)';
const kLongDone = 'запись журнала с длинным описанием';

class FakeTimerStore extends TimerStateStore {
  @override
  Future<TimerSnapshot?> load() async => null;

  @override
  Future<void> save(TimerSnapshot snapshot) async {}
}

class FakeTasks implements TaskRepository {
  @override
  Future<Either<Failure, TasksFile>> load() async => Either.right(
    TasksFile(
      todo: [
        PomoTask(
          id: 't1',
          description: kLongTodo,
          category: 'заработок',
          durationMinutes: 50,
          frog: true,
          week: true,
        ),
      ],
      planner: [
        PomoTask(
          id: 'p1',
          description: kLongPlanned,
          category: 'заработок',
          durationMinutes: 25,
          week: true,
        ),
        PomoTask(
          id: 'p2',
          description: 'задача на завтра',
          category: 'pixelByte',
          durationMinutes: 25,
          due: DateTime.now().add(const Duration(days: 1)),
        ),
      ],
    ),
  );

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile file) async =>
      Either.right(unit);
}

class FakeJournal implements JournalRepository {
  @override
  Future<Either<Failure, Unit>> addSession(PomoSession s, int goal) async =>
      Either.right(unit);

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) async => Either.right(unit);

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int goal) async =>
      Either.right(_day(date, goal));

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int goal,
  ) async {
    final days = <DayLog>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    while (!cursor.isAfter(last)) {
      days.add(_day(cursor, goal));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return Either.right(days);
  }

  DayLog _day(DateTime date, int goal) => DayLog(
    date: date,
    goal: goal,
    sessions: [
      PomoSession(
        id: '${date.day}-1',
        start: DateTime(date.year, date.month, date.day, 9),
        minutes: 25,
        category: 'заработок',
        task: kLongDone,
        manual: true,
      ),
    ],
  );
}

class FakeSprints implements SprintRepository {
  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int goal) async =>
      Either.right(
        Sprint(
          id: '2026-W30',
          start: now,
          goal: goal,
          milestone: 'веха недели с довольно длинным описанием цели',
          doneWeek: const ['✅ 20.07 закрытая задача недели #заработок'],
        ),
      );

  @override
  Future<Either<Failure, Unit>> saveSprint(
    Sprint sprint,
    List<DayLog> fact, {
    List<PomoTask> weekTasks = const [],
  }) async => Either.right(unit);

  @override
  Future<Either<Failure, List<SprintSummary>>> history() async =>
      Either.right(const [
        SprintSummary(id: '2026-W29', goal: 40, fact: 31, minutes: 775),
      ]);
}

class FakeSettings implements SettingsRepository {
  @override
  Future<Either<Failure, AppSettings>> load() async =>
      Either.right(AppSettings.fromJson(const {}, fallbackPath: '.'));

  @override
  Future<Either<Failure, Unit>> save(AppSettings s) async => Either.right(unit);
}

/// Собранный набор кубитов; [dispose] обязателен ДО конца теста —
/// JournalCubit держит периодический таймер, и биндинг ругается на него
/// раньше, чем отработает teardown.
class ScreenHarness {
  ScreenHarness(this.dispose);

  final Future<void> Function() dispose;
}

/// Поднять экран [screen] на ширине [size] со всеми кубитами.
Future<ScreenHarness> pumpScreen(
  WidgetTester tester,
  Size size,
  Widget screen,
) async {
  tester.view
    ..physicalSize = size
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
    FakeSprints(),
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
        ],
        child: Scaffold(body: screen),
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
    await settings.close();
  });
}

/// Ширина, доставшаяся тексту внутри строки списка.
///
/// Проверка переполнения такого не ловит: зажатый текст просто переносится,
/// и RenderFlex молчит — поэтому меряем явно.
double rowTextWidth(WidgetTester tester, String text) {
  final inRow = find
      .descendant(of: find.byType(ListTile), matching: find.text(text))
      .first;
  return tester.getSize(inRow).width;
}
