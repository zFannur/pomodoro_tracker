import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/presentation/widgets/cause_chips.dart';
import 'package:pomodoro_tracker/presentation/widgets/episode_sheet.dart';
import 'package:pomodoro_tracker/presentation/widgets/first_step_field.dart';
import 'package:pomodoro_tracker/presentation/home_shell.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

const episodeTask = PomoTask(
  id: 'task',
  description: 'Подключить webhook',
  category: 'работа',
  durationMinutes: 25,
);

class _MemoryActivityStore extends ActivityStore {
  @override
  Future<ActivityData> load() async => ActivityData();

  @override
  Future<void> save(ActivityData data) async {}
}

Future<void> press(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  final finder = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<ScreenHarness> openEpisode(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  PomoTask? task = episodeTask,
  Episode? existing,
  EpisodeInsight? insight,
  EpisodeTasks? tasks,
  EpisodeTimer? timer,
  DirectionsCubit? directions,
}) async {
  final harness = await pumpScreen(
    tester,
    size,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showEpisodeSheet(
          context,
          source: EpisodeSource.manual,
          task: task,
          existing: existing,
        ),
        child: const Text('open'),
      ),
    ),
    tasksCubit: tasks,
    timerCubit: timer,
    insightCubit: insight ?? EpisodeInsight(),
    directionsCubit: directions,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('старт из переноса активирует нужную задачу планировщика', (
    tester,
  ) async {
    final tasks = EpisodeTasks()
      ..seed(
        todo: [episodeTask.copyWith(id: 'other')],
        planner: [episodeTask],
      );
    final timer = EpisodeTimer();
    final h = await openEpisode(
      tester,
      tasks: tasks,
      timer: timer,
      insight: EpisodeInsight(order: [StrategyKind.defuse]),
    );
    await press(tester, S.cause(Cause.perfect));
    await press(tester, S.actionWarmup);
    expect(tasks.state.current?.id, episodeTask.id);
    expect(tasks.state.planner, isEmpty);
    expect(timer.warmups, [10]);
    await h.dispose();
  });

  testWidgets(
    'value возвращает просроченную задачу из планировщика без переноса',
    (tester) async {
      final task = episodeTask.copyWith(due: DateTime(2000), deferrals: 3);
      final tasks = EpisodeTasks()..seed(planner: [task]);
      var deferred = false;
      tasks.onDeferred = (_) async {
        deferred = true;
      };
      final h = await openEpisode(
        tester,
        task: task,
        tasks: tasks,
        insight: EpisodeInsight(order: [StrategyKind.value]),
      );
      await press(tester, S.cause(Cause.pointless));
      await press(tester, S.actionToInbox);
      expect(tasks.state.planner.single.due, isNull);
      expect(tasks.state.planner.single.deferrals, 3);
      expect(deferred, false);
      await h.dispose();
    },
  );

  testWidgets('firstStep сохраняет план старой задачи без id', (tester) async {
    const task = PomoTask(
      description: 'Старая задача',
      category: 'дело',
      durationMinutes: 25,
    );
    final tasks = EpisodeTasks()..seed(todo: [task]);
    final h = await openEpisode(tester, task: task, tasks: tasks);
    await press(tester, S.cause(Cause.unclear));
    await enter(tester, S.fieldFirstStep, 'Открыть файл');
    await press(tester, S.actionSaveWarmup);
    expect(tasks.state.current?.firstStep, 'Открыть файл');
    await h.dispose();
  });

  testWidgets(
    'HomeShell: перенос №3 открывает тихий эпизод с актуальной задачей',
    (tester) async {
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final tracker = ActivityTracker(
        store: _MemoryActivityStore(),
        inPomodoro: () => false,
      );
      final activity = ActivityCubit(tracker);
      final insight = EpisodeInsight();
      final tasks = EpisodeTasks()..seed(planner: [episodeTask]);
      final h = await pumpScreen(
        tester,
        const Size(1280, 900),
        BlocProvider.value(value: activity, child: const HomeShell()),
        tasksCubit: tasks,
        insightCubit: insight,
        timerCubit: EpisodeTimer(),
      );
      final episode = await insight.addEpisode(
        source: EpisodeSource.defer,
        task: episodeTask,
      );
      insight.reportDeferral(episode, 2);
      await tester.pumpAndSettle();
      expect(find.text(S.deferralSnack(2)), findsNothing);
      insight.reportDeferral(episode, 3);
      await tester.pumpAndSettle();
      expect(find.text(S.deferralSnack(3)), findsOneWidget);
      tasks.seed(
        planner: [episodeTask.copyWith(description: 'Уточнённая задача')],
      );
      await press(tester, S.deferralAction);
      expect(find.text('Уточнённая задача'), findsOneWidget);
      await press(tester, S.cause(Cause.boring));
      expect(insight.episodes, hasLength(1));
      expect(insight.episodes.single.source, EpisodeSource.defer);
      expect(insight.episodes.single.cause, Cause.boring);
      expect(tester.takeException(), isNull);
      await h.dispose();
      await tester.runAsync(activity.close);
      // Трекер не запускался и не писал настоящие файлы.
      await tester.runAsync(tracker.dispose);
    },
  );

  testWidgets('семь причин по порядку; тап сразу сохраняет мысль и причину', (
    tester,
  ) async {
    final insight = EpisodeInsight();
    final h = await openEpisode(tester, insight: insight);
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(chips.map((c) => (c.label as Text).data), Cause.values.map(S.cause));
    await enter(tester, S.episodeThought, 'надо сразу идеально');
    await press(tester, S.cause(Cause.perfect));
    expect(insight.episodes.single.cause, Cause.perfect);
    expect(insight.episodes.single.thought, 'надо сразу идеально');
    await tester.tap(find.byTooltip(S.close));
    await tester.pumpAndSettle();
    expect(insight.episodes, hasLength(1));
    expect(insight.episodes.single.strategy, isNull);
    await h.dispose();
  });

  testWidgets('неделя наблюдения и явный переход к помощи', (tester) async {
    final h = await openEpisode(
      tester,
      insight: EpisodeInsight(observing: true),
    );
    await press(tester, S.cause(Cause.unclear));
    expect(find.text(S.observationNote), findsOneWidget);
    expect(find.byType(FirstStepField), findsNothing);
    await press(tester, S.observationHelp);
    expect(find.byType(FirstStepField), findsOneWidget);
    await h.dispose();
  });

  testWidgets('только отметить закрывает лист без способа и таймера', (
    tester,
  ) async {
    final insight = EpisodeInsight();
    final timer = EpisodeTimer();
    final h = await openEpisode(tester, insight: insight, timer: timer);
    await press(tester, S.cause(Cause.boring));
    await press(tester, S.episodeJustMark);
    expect(find.byType(CauseChips), findsNothing);
    expect(insight.episodes.single.strategy, isNull);
    expect(timer.warmups, isEmpty);
    await h.dispose();
  });

  testWidgets('первый способ из ranked и статистика от трёх попыток', (
    tester,
  ) async {
    final h = await openEpisode(
      tester,
      insight: EpisodeInsight(
        order: [StrategyKind.warmup, StrategyKind.firstStep],
        counts: {
          StrategyKind.warmup: (tries: 5, wins: 4),
          StrategyKind.firstStep: (tries: 2, wins: 1),
        },
      ),
    );
    await press(tester, S.cause(Cause.big));
    expect(find.text(S.strategyBody(StrategyKind.warmup)), findsOneWidget);
    expect(find.text(S.episodeHelped(4, 5)), findsOneWidget);
    await press(tester, S.strategyTitle(StrategyKind.firstStep));
    expect(find.byType(FirstStepField), findsOneWidget);
    expect(find.text(S.episodeHelped(1, 2)), findsNothing);
    await h.dispose();
  });

  testWidgets('firstStep пишет план и запускает разгон 10 минут', (
    tester,
  ) async {
    final insight = EpisodeInsight();
    final tasks = EpisodeTasks()..seed(todo: [episodeTask]);
    final timer = EpisodeTimer();
    final h = await openEpisode(
      tester,
      insight: insight,
      tasks: tasks,
      timer: timer,
    );
    await press(tester, S.cause(Cause.unclear));
    await enter(tester, S.fieldFirstStep, 'Открыть dashboard');
    await press(tester, S.actionSaveWarmup);
    expect(tasks.plans.single.step, 'Открыть dashboard');
    expect(tasks.plans.single.id, 'task');
    expect(timer.warmups, [10]);
    expect(insight.episodes.single.strategy, StrategyKind.firstStep);
    expect(find.text(S.episodeTry), findsNothing);
    await h.dispose();
  });

  testWidgets('нет задачи — нет firstStep, ifThen, shrink', (tester) async {
    final h = await openEpisode(tester, task: null);
    await press(tester, S.cause(Cause.big));
    for (final kind in [
      StrategyKind.firstStep,
      StrategyKind.ifThen,
      StrategyKind.shrink,
    ]) {
      expect(find.text(S.strategyTitle(kind)), findsNothing);
    }
    expect(find.text(S.strategyTitle(StrategyKind.warmup)), findsOneWidget);
    await h.dispose();
  });

  testWidgets('тихий эпизод дозаполняется, новый не создаётся', (tester) async {
    final insight = EpisodeInsight();
    final existing = await insight.addEpisode(
      source: EpisodeSource.distract,
      app: 'YouTube',
      task: episodeTask,
    );
    final h = await openEpisode(tester, insight: insight, existing: existing);
    await press(tester, S.cause(Cause.external));
    expect(insight.episodes, hasLength(1));
    expect(insight.causeUpdates, 1);
    expect(insight.episodes.single.source, EpisodeSource.distract);
    expect(insight.episodes.single.app, 'YouTube');
    expect(find.text(S.episodeTry), findsOneWidget);
    await h.dispose();
  });

  testWidgets('ошибка записи не запускает таймер и позволяет повторить', (
    tester,
  ) async {
    final insight = EpisodeInsight()..failWrite = true;
    final timer = EpisodeTimer();
    final h = await openEpisode(tester, insight: insight, timer: timer);
    await press(tester, S.cause(Cause.boring));
    expect(find.textContaining('write failed'), findsOneWidget);
    expect(timer.warmups, isEmpty);
    insight.failWrite = false;
    await press(tester, S.cause(Cause.tired));
    await press(tester, S.actionWarmup);
    expect(timer.warmups, [10]);
    expect(insight.episodes, hasLength(1));
    await h.dispose();
  });

  for (final start in [false, true]) {
    testWidgets('ifThen сохраняет cue, cueAt и первый шаг, разгон=$start', (
      tester,
    ) async {
      final task = episodeTask.copyWith(cueAt: '09:30');
      final tasks = EpisodeTasks()..seed(todo: [task]);
      final timer = EpisodeTimer();
      final h = await openEpisode(
        tester,
        task: task,
        tasks: tasks,
        timer: timer,
        insight: EpisodeInsight(order: [StrategyKind.ifThen]),
      );
      await press(tester, S.cause(Cause.unclear));
      await enter(tester, S.fieldFirstStep, 'Открыть файл');
      await enter(tester, S.fieldCue, 'сяду после завтрака');
      await press(tester, start ? S.actionSaveWarmup : S.actionSave);
      expect(tasks.plans.single, (
        id: 'task',
        step: 'Открыть файл',
        cue: 'сяду после завтрака',
        time: '09:30',
      ));
      expect(timer.warmups, start ? [10] : isEmpty);
      await h.dispose();
    });
  }

  testWidgets('shrink добавляет один помидор наверх и стартует', (
    tester,
  ) async {
    final tasks = EpisodeTasks()..seed(todo: [episodeTask]);
    final timer = EpisodeTimer();
    final h = await openEpisode(
      tester,
      tasks: tasks,
      timer: timer,
      insight: EpisodeInsight(order: [StrategyKind.shrink]),
    );
    await press(tester, S.cause(Cause.big));
    await enter(tester, S.fieldShrink, 'Один обработчик');
    await press(tester, S.actionAddStart);
    expect(tasks.state.current?.description, 'Один обработчик');
    expect(tasks.state.current?.category, episodeTask.category);
    expect(
      tasks.state.current?.durationMinutes,
      episodeSettings().scheme.pomodoro,
    );
    expect(timer.starts, 1);
    await h.dispose();
  });

  testWidgets('thought сохраняет три поля, defuse показывает мысль', (
    tester,
  ) async {
    final insight = EpisodeInsight(
      order: [StrategyKind.thought, StrategyKind.defuse],
    );
    final timer = EpisodeTimer();
    final h = await openEpisode(tester, insight: insight, timer: timer);
    await enter(tester, S.episodeThought, 'всё плохо');
    await press(tester, S.cause(Cause.perfect));
    await press(tester, S.strategyTitle(StrategyKind.defuse));
    expect(find.text(S.defuseLine('всё плохо')), findsOneWidget);
    await press(tester, S.strategyTitle(StrategyKind.thought));
    await enter(tester, S.fieldThought, 'нужен идеал');
    await enter(tester, S.fieldFact, 'есть черновик');
    await enter(tester, S.fieldAlt, 'попробую черновик');
    await press(tester, S.actionSaveWarmup);
    expect(insight.episodes.single.thought, 'нужен идеал');
    expect(insight.episodes.single.fact, 'есть черновик');
    expect(insight.episodes.single.alt, 'попробую черновик');
    expect(timer.warmups, [10]);
    await h.dispose();
  });

  testWidgets('value сохраняет пустое why направления', (tester) async {
    final directions = DirectionsCubit(FakeCourse());
    final h = await openEpisode(
      tester,
      directions: directions,
      insight: EpisodeInsight(order: [StrategyKind.value]),
    );
    directions.emit(
      const DirectionsState(
        status: DirectionsStatus.ready,
        directions: [
          Direction(id: 'dir', name: 'Дело', categories: ['работа']),
        ],
      ),
    );
    await press(tester, S.cause(Cause.pointless));
    await enter(tester, S.fieldWhy, 'Свобода');
    await press(tester, S.actionWarmup);
    expect(directions.state.directions.single.why, 'Свобода');
    await h.dispose();
  });

  testWidgets('value без направления возвращает во Входящие без переноса', (
    tester,
  ) async {
    final tasks = EpisodeTasks()..seed(todo: [episodeTask]);
    final timer = EpisodeTimer();
    final h = await openEpisode(
      tester,
      tasks: tasks,
      timer: timer,
      insight: EpisodeInsight(order: [StrategyKind.value]),
    );
    await press(tester, S.cause(Cause.pointless));
    expect(find.text(S.valueNoDirection), findsOneWidget);
    await press(tester, S.actionToInbox);
    expect(tasks.countedDeferral, false);
    expect(tasks.state.planner.single.deferrals, 0);
    expect(timer.warmups, isEmpty);
    await h.dispose();
  });

  testWidgets('rest с паузы явно стопает и запускает отдых 10 минут', (
    tester,
  ) async {
    final timer = EpisodeTimer()..seed(run: TimerRun.paused, remaining: 1000);
    final h = await openEpisode(
      tester,
      timer: timer,
      insight: EpisodeInsight(order: [StrategyKind.rest]),
    );
    await press(tester, S.cause(Cause.tired));
    await press(tester, S.actionRest);
    expect(timer.stops, 1);
    expect(timer.rests, [10]);
    await h.dispose();
  });

  for (final run in TimerRun.values) {
    testWidgets('removeCue кладёт мысль во Входящие, run=$run', (tester) async {
      final timer = EpisodeTimer()..seed(run: run, remaining: 1000);
      final tasks = EpisodeTasks()..seed(todo: [episodeTask]);
      final h = await openEpisode(
        tester,
        timer: timer,
        tasks: tasks,
        insight: EpisodeInsight(order: [StrategyKind.removeCue]),
      );
      await press(tester, S.cause(Cause.external));
      await enter(tester, S.fieldToInbox, 'купить воду');
      await press(tester, S.actionContinue);
      expect(tasks.inbox, ['купить воду']);
      expect(timer.starts, run == TimerRun.stopped ? 1 : 0);
      expect(timer.resumes, run == TimerRun.paused ? 1 : 0);
      expect(timer.warmups, isEmpty);
      await h.dispose();
    });
  }

  for (final kind in StrategyKind.values) {
    testWidgets('идущий помидор не перезапускается способом $kind', (
      tester,
    ) async {
      final task = episodeTask.copyWith(
        firstStep: 'Открыть файл',
        cue: 'после чая',
      );
      final timer = EpisodeTimer()..seed(run: TimerRun.running, remaining: 987);
      final tasks = EpisodeTasks()..seed(todo: [task]);
      final h = await openEpisode(
        tester,
        task: task,
        timer: timer,
        tasks: tasks,
        insight: EpisodeInsight(order: [kind]),
      );
      await press(tester, S.cause(Cause.big));
      await press(tester, S.actionContinue);
      expect(timer.state.remaining, 987);
      expect(timer.warmups, isEmpty);
      expect(timer.rests, isEmpty);
      expect(timer.starts + timer.resumes + timer.stops, 0);
      expect(tasks.smaller, isEmpty);
      await h.dispose();
    });
  }

  for (final size in [const Size(375, 812), const Size(1280, 900)]) {
    testWidgets('лист и все карточки без переполнения ${size.width}', (
      tester,
    ) async {
      final h = await openEpisode(
        tester,
        size: size,
        insight: EpisodeInsight(order: StrategyKind.values),
      );
      expect(
        find.byType(Dialog),
        size.width < 600 ? findsNothing : findsOneWidget,
      );
      if (size.width >= 600) {
        final content = find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 460,
          ),
        );
        expect(tester.getSize(content).width, 460);
      }
      expect(tester.takeException(), isNull);
      await press(tester, S.cause(Cause.big));
      for (final kind in StrategyKind.values) {
        if (kind != StrategyKind.firstStep) {
          await press(tester, S.strategyTitle(kind));
        }
        expect(tester.takeException(), isNull, reason: '$kind');
      }
      await h.dispose();
    });
  }
}
