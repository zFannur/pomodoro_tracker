import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/data/timer_state_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/timer_screen.dart';
import 'package:pomodoro_tracker/presentation/widgets/common.dart';
import 'package:pomodoro_tracker/presentation/widgets/first_step_field.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';
import 'screen_fakes.dart';

class MemoryStore extends TimerStateStore {
  TimerSnapshot? snapshot;
  @override
  Future<TimerSnapshot?> load() async => snapshot;
  @override
  Future<void> save(TimerSnapshot value) async {
    snapshot = value;
  }
}

void main() {
  AppSettings settings() =>
      AppSettings.fromJson(const {}, fallbackPath: '.').copyWith(
        flowtime: false,
        notifications: false,
        notifyTelegram: false,
        tickingSound: false,
        finishSoundEnabled: false,
        notifyMinuteBefore: false,
        popupRaiseWindow: false,
      );
  TimerCubit timer(MemoryStore store, List<PomodoroResult> results) =>
      TimerCubit(
        settings: settings,
        sound: SoundService(),
        notify: NotifyService(),
        store: store,
        hasTodos: () => true,
        onPomodoroComplete: (r) async {
          results.add(r);
        },
      );

  test('разгон переходит в overtime и записывает фактическое время', () {
    fakeAsync((async) {
      final results = <PomodoroResult>[];
      final cubit = timer(MemoryStore(), results);
      cubit.startWarmup(10);
      async.elapse(const Duration(minutes: 12));
      expect(cubit.state.inOvertime, isTrue);
      cubit.doneEarly();
      async.flushMicrotasks();
      expect(results.single.warmup, isTrue);
      expect(results.single.workedMinutes, 12);
      expect(cubit.state.warmup, isFalse);
      cubit.close();
    });
  });

  test('пауза возобновляется; снимок сохраняет и восстанавливает разгон', () {
    fakeAsync((async) {
      final store = MemoryStore();
      final cubit = timer(store, []);
      cubit.startWarmup(10);
      async.elapse(const Duration(seconds: 20));
      cubit.pause();
      cubit.startWarmup(4);
      expect(cubit.state.running, isTrue);
      expect(cubit.state.total, 600);
      async.flushMicrotasks();
      final restored = timer(store, []);
      restored.restore();
      async.flushMicrotasks();
      expect(restored.state.warmup, isTrue);
      expect(TimerSnapshot.fromJson(store.snapshot!.toJson())!.warmup, isTrue);
      expect(TimerSnapshot.fromJson({'savedAt': 0})!.warmup, isFalse);
      cubit.close();
      restored.close();
    });
  });

  test('отдых сохраняет серию', () {
    fakeAsync((async) {
      final cubit = timer(MemoryStore(), []);
      cubit.forward();
      expect(cubit.state.series, 1);
      cubit.startRest(10);
      expect(cubit.state.mode, TimerMode.shortBreak);
      expect(cubit.state.remaining, 600);
      expect(cubit.state.series, 1);
      cubit.close();
    });
  });

  test('планы по id, уменьшение задачи и фактическое списание', () async {
    final cubit = TasksCubit(
      FakeTasks(),
      FakeJournal(),
      settings,
      NotifyService(),
    );
    await cubit.load();
    await cubit.setPlan('t1', firstStep: 'шаг', cue: 'утро', cueAt: '09:30');
    await cubit.setPlan('p1', firstStep: 'план');
    expect(cubit.state.todo.first.firstStep, 'шаг');
    expect(cubit.state.planner.first.firstStep, 'план');
    await cubit.completeFromTimer(
      PomodoroResult(
        workedMinutes: 12,
        delayMs: 0,
        interruptions: 0,
        startedAt: DateTime(2026),
        warmup: true,
      ),
    );
    expect(cubit.state.todo.first.durationMinutes, 38);
    final parent = cubit.state.todo.first;
    await cubit.addSmaller(parent, 'меньше');
    expect(cubit.state.todo.first.description, 'меньше');
    expect(cubit.state.todo.first.category, parent.category);
    expect(cubit.state.todo.first.durationMinutes, settings().scheme.pomodoro);
    expect(cubit.state.todo.first.frog, isFalse);
    await cubit.close();
  });

  testWidgets('редактор возвращает план', (tester) async {
    final settingsCubit = SettingsCubit(
      FakeSettings(),
      initial: settings(),
      onStoragePathChanged: (_) {},
    );
    ({
      String category,
      String description,
      int? minutes,
      String firstStep,
      String cue,
      String cueAt,
    })?
    result;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: settingsCubit,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showTaskEditDialog(
                    context,
                    title: 'Edit',
                    category: 'test',
                    description: 'task',
                    cueAt: '09:30',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(FirstStepField),
        matching: find.byType(TextField),
      ),
      'шаг',
    );
    await tester.enterText(
      find.widgetWithText(TextField, S.cueLabel),
      'после завтрака',
    );
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();
    expect(result?.firstStep, 'шаг');
    expect(result?.cue, 'после завтрака');
    expect(result?.cueAt, '09:30');
    await tester.pumpWidget(const SizedBox());
    await settingsCubit.close();
  });

  testWidgets('СЕЙЧАС показывает только непустой шаг', (tester) async {
    final harness = await pumpScreen(
      tester,
      const Size(1000, 900),
      const TimerScreen(),
    );
    final context = tester.element(find.byType(TimerScreen));
    final tasks = context.read<TasksCubit>();
    expect(find.text('▸ шаг'), findsNothing);
    await tasks.setPlan('t1', firstStep: 'шаг');
    await tester.pump();
    expect(find.text('▸ шаг'), findsOneWidget);
    await tasks.setPlan('t1', firstStep: '');
    await tester.pump();
    expect(find.text('▸ шаг'), findsNothing);
    await harness.dispose();
  });
}
