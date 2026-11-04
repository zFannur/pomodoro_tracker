import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/data/timer_state_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/journal_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/timer_screen.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';
import 'package:pomodoro_tracker/presentation/widgets/cause_chips.dart';

import 'screen_fakes.dart' show FakeInsights, FakeSprints;
import 'screen_fakes.dart' show pumpScreen;
import 'episode_fakes.dart';

class _FakeStore extends TimerStateStore {
  @override
  Future<TimerSnapshot?> load() async => null;

  @override
  Future<void> save(TimerSnapshot snapshot) async {}
}

/// Задачи с длинными описаниями — именно на них ряд и разъезжался.
class _MemTasks implements TaskRepository {
  @override
  Future<Either<Failure, TasksFile>> load() async => Either.right(
    TasksFile(
      todo: [
        PomoTask(
          id: 't1',
          description: 'настроить ci/cd для репо видеоаналитики',
          category: 'Uzum',
          durationMinutes: 50,
          frog: true,
          week: true,
        ),
        PomoTask(
          id: 't2',
          description: 'КВОРК 1 — Telegram Mini App (флагман)',
          category: 'заработок',
          durationMinutes: 25,
        ),
      ],
      planner: const [],
    ),
  );

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile file) async =>
      Either.right(unit);
}

class _MemJournal implements JournalRepository {
  @override
  Future<Either<Failure, Unit>> addSession(PomoSession s, int goal) async =>
      Either.right(unit);

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) async => Either.right(unit);

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int goal) async =>
      Either.right(
        DayLog(
          date: date,
          goal: goal,
          sessions: [
            PomoSession(
              id: 'p1',
              start: DateTime(date.year, date.month, date.day, 9),
              minutes: 25,
              category: 'заработок',
              task: 'запись журнала с длинным описанием',
              manual: true,
            ),
          ],
        ),
      );

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int goal,
  ) async => Either.right(const []);
}

class _MemSettings implements SettingsRepository {
  @override
  Future<Either<Failure, AppSettings>> load() async =>
      Either.right(AppSettings.fromJson(const {}, fallbackPath: '.'));

  @override
  Future<Either<Failure, Unit>> save(AppSettings s) async => Either.right(unit);
}

class _MemCourse implements DirectionRepository {
  _MemCourse({this.directions = const [], this.milestones = const []});

  final List<Direction> directions;
  final List<Milestone> milestones;

  @override
  Future<Either<Failure, Course>> loadCourse() async =>
      Either.right((directions: directions, milestones: milestones));

  @override
  Future<Either<Failure, Unit>> saveCourse(Course course) async =>
      Either.right(unit);
}

void main() {
  testWidgets('чип простоя только с 10 минут и при наличии задач', (tester) async {
    final timer = EpisodeTimer()..seed(delay: 9 * 60000);
    final tasks = EpisodeTasks()..seed(todo: [const PomoTask(id: 't', description: 'Задача', category: 'дело', durationMinutes: 25)]);
    final insight = EpisodeInsight();
    final h = await pumpScreen(tester, const Size(375, 812), const TimerScreen(),
      timerCubit: timer, tasksCubit: tasks, insightCubit: insight);
    expect(find.text(S.stuckChip), findsNothing);
    timer.seed(delay: 10 * 60000);
    await tester.pump();
    await tester.pump();
    expect(find.text(S.stuckChip), findsOneWidget);
    await tester.tap(find.text(S.stuckChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.cause(Cause.boring)));
    await tester.pumpAndSettle();
    expect(insight.episodes.single.source, EpisodeSource.idle);
    await tester.tap(find.text(S.episodeJustMark));
    await tester.pumpAndSettle();
    tasks.seed();
    await tester.pump();
    await tester.pump();
    expect(find.text(S.stuckChip), findsNothing);
    expect(find.text(S.stuckHint), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  for (final run in [TimerRun.stopped, TimerRun.paused]) {
    testWidgets('«Не идёт» открывает manual, $run', (tester) async {
      final insight = EpisodeInsight();
      final timer = EpisodeTimer()..seed(run: run, remaining: 1000);
      final h = await pumpScreen(tester, const Size(375, 812), const TimerScreen(),
        insightCubit: insight, timerCubit: timer);
      await tester.tap(find.byTooltip(S.notGoing));
      await tester.pumpAndSettle();
      expect(find.byType(CauseChips), findsOneWidget);
      await tester.tap(find.text(S.cause(Cause.tired)));
      await tester.pumpAndSettle();
      expect(insight.episodes.single.source, EpisodeSource.manual);
      expect(tester.takeException(), isNull);
      await h.dispose();
    });
  }

  testWidgets('чип отвлечения открывает существующий эпизод без перезапуска', (tester) async {
    final insight = EpisodeInsight();
    await insight.addEpisode(source: EpisodeSource.distract, app: 'YouTube');
    final timer = EpisodeTimer()..seed(run: TimerRun.running, remaining: 987);
    final h = await pumpScreen(tester, const Size(375, 812), const TimerScreen(),
      insightCubit: insight, timerCubit: timer);
    expect(find.byTooltip(S.notGoing), findsNothing);
    await tester.tap(find.text(S.distractedChip('YouTube')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.cause(Cause.external)));
    await tester.pumpAndSettle();
    expect(insight.episodes, hasLength(1));
    await tester.tap(find.text(S.actionContinue));
    await tester.pumpAndSettle();
    expect(timer.state.remaining, 987);
    expect(timer.starts + timer.resumes, 0);
    expect(find.text(S.distractedChip('YouTube')), findsNothing);
    await h.dispose();
  });

  for (final choice in ['cause', 'finished', 'none']) {
    for (final save in [false, true]) {
      testWidgets('стоп: $choice, сохранить заметку=$save', (tester) async {
        final insight = EpisodeInsight();
        final timer = EpisodeTimer()..seed(run: TimerRun.running, remaining: 1000);
        final h = await pumpScreen(tester, const Size(375, 812), const TimerScreen(),
          insightCubit: insight, timerCubit: timer);
        await tester.tap(find.text(S.stop));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNWidgets(8));
        await tester.enterText(find.byType(TextFormField), 'дописал обработчик');
        if (choice != 'none') {
          final chip = find.text(choice == 'cause' ? S.cause(Cause.big) : S.causeFinished);
          await tester.ensureVisible(chip);
          await tester.tap(chip);
          await tester.pump();
        }
        final button = find.text(save ? S.save : S.withoutNote);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(insight.episodes, hasLength(choice == 'cause' ? 1 : 0));
        if (choice == 'cause') {
          expect(insight.episodes.single.source, EpisodeSource.stop);
          expect(insight.episodes.single.cause, Cause.big);
          expect(insight.episodes.single.thought, isEmpty);
          expect(insight.episodes.single.strategy, isNull);
          expect(insight.episodes.single.taskId, 't1');
        }
        expect(tester.takeException(), isNull);
        await h.dispose();
      });
    }
  }

  /// Главный экран уже разъезжался на телефоне: описанию задачи оставалось
  /// ~40dp и текст рвался по слогам. Поэтому ловим переполнение раскладки.
  Future<Future<void> Function()> pumpAt(
    WidgetTester tester,
    Size size, {
    DirectionRepository? courseRepo,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = SettingsCubit(
      _MemSettings(),
      initial: AppSettings.fromJson(const {}, fallbackPath: '.'),
      onStoragePathChanged: (_) {},
    );
    await settings.load();
    AppSettings current() => settings.state.settings;

    final journalRepo = _MemJournal();
    final insight = InsightCubit(FakeInsights(), journalRepo, FakeSprints(), current);
    await insight.refresh();
    final tasks = TasksCubit(
      _MemTasks(),
      journalRepo,
      current,
      NotifyService(),
    );
    await tasks.load();

    final journal = JournalCubit(
      journalRepo,
      current,
      NotifyService(),
      onDayChanged: () async {},
    );
    await journal.refresh();

    final timer = TimerCubit(
      settings: current,
      sound: SoundService(),
      notify: NotifyService(),
      store: _FakeStore(),
      hasTodos: () => true,
      onPomodoroComplete: (_) async {},
    );

    DirectionsCubit? directions;
    if (courseRepo != null) {
      directions = DirectionsCubit(courseRepo, journalRepo);
      await directions.refresh();
    }

    // Закрывать нужно ДО конца теста, а не в teardown: JournalCubit держит
    // периодический таймер, и биндинг ругается на него раньше teardown.
    Future<void> dispose() async {
      await tasks.close();
      await insight.close();
      await journal.close();
      await timer.close();
      await directions?.close();
      await settings.close();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settings),
            BlocProvider.value(value: tasks),
            BlocProvider.value(value: journal),
            BlocProvider.value(value: timer),
            BlocProvider.value(value: insight),
            if (directions != null) BlocProvider.value(value: directions),
          ],
          child: const Scaffold(body: TimerScreen()),
        ),
      ),
    );
    await tester.pump();
    return dispose;
  }

  testWidgets('главный экран строится на телефоне', (tester) async {
    final dispose = await pumpAt(tester, const Size(411, 850));
    expect(tester.takeException(), isNull);
    expect(find.byType(TimerScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await dispose();
  });

  testWidgets('на экране таймера нет кнопки «Планировщик»', (tester) async {
    final dispose = await pumpAt(tester, const Size(411, 850));

    expect(find.text('Планировщик'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await dispose();
  });

  testWidgets('описаниям на телефоне достаётся ширина, а не колонка в букву',
      (tester) async {
    // Проверка переполнения этого не ловит: зажатый текст просто переносится,
    // а RenderFlex молчит. Поэтому меряем, сколько места реально досталось.
    final dispose = await pumpAt(tester, const Size(411, 850));
    for (final text in const [
      'настроить ci/cd для репо видеоаналитики', // «Запланировано»
      'запись журнала с длинным описанием', // «Сделано»
    ]) {
      // Именно строка списка: то же описание есть и в карточке «СЕЙЧАС»,
      // где оно живёт по своим правилам и режется многоточием.
      final inRow = find
          .descendant(of: find.byType(ListTile), matching: find.text(text))
          .first;
      final width = tester.getSize(inRow).width;
      // Порог сторожит возврат к патологии (было ~40dp — буквы в столбик),
      // а не идеальную вёрстку: остальное съедают отступы карточки и
      // счётчик помидоров с меню справа.
      expect(
        width,
        greaterThan(411 * 0.4),
        reason: 'описанию «$text» осталось ${width.round()}dp из 411',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await dispose();
  });

  testWidgets('главный экран строится на широком экране', (tester) async {
    final dispose = await pumpAt(tester, const Size(1280, 900));
    expect(tester.takeException(), isNull);
    expect(find.byType(TimerScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await dispose();
  });

  testWidgets(
      'нить отображается, если категория задачи принадлежит направлению',
      (tester) async {
    // В _MemTasks текущая задача t1 имеет категорию 'Uzum'.
    // Привязываем категорию к направлению с открытой вехой.
    final courseRepo = _MemCourse(
      directions: const [
        Direction(
          id: 'd1',
          name: 'Маркетплейс',
          categories: ['Uzum'],
        ),
      ],
      milestones: const [
        Milestone(
          id: 'm1',
          directionId: 'd1',
          title: 'Первая продажа',
          order: 0,
        ),
      ],
    );

    final dispose = await pumpAt(
      tester,
      const Size(411, 850),
      courseRepo: courseRepo,
    );

    expect(find.text('Маркетплейс → Первая продажа'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await dispose();
  });

  testWidgets(
      'нить отсутствует, если категория не принадлежит ни одному направлению',
      (tester) async {
    // Направление есть, но для другой категории ('Кворк' вместо 'Uzum').
    final courseRepo = _MemCourse(
      directions: const [
        Direction(
          id: 'd1',
          name: 'Фриланс',
          categories: ['Кворк'],
        ),
      ],
      milestones: const [
        Milestone(
          id: 'm1',
          directionId: 'd1',
          title: 'Первый заказ',
          order: 0,
        ),
      ],
    );

    final dispose = await pumpAt(
      tester,
      const Size(411, 850),
      courseRepo: courseRepo,
    );

    // Ни название направления, ни стрелка нити не должны появиться в карточке СЕЙЧАС
    expect(find.textContaining('Фриланс'), findsNothing);
    expect(find.textContaining('→'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await dispose();
  });
}

