import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/timer_state_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart'
    show parseSmartInput;
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';

/// Стор-заглушка: без платформенных каналов.
class _FakeStore extends TimerStateStore {
  @override
  Future<TimerSnapshot?> load() async => null;

  @override
  Future<void> save(TimerSnapshot snapshot) async {}
}

void main() {
  AppSettings silentSettings() {
    return AppSettings.fromJson(const {}, fallbackPath: '.').copyWith(
      schemes: const [
        TimerScheme(
          name: 'test',
          pomodoro: 1,
          shortBreak: 1,
          longBreak: 2,
          longEvery: 2,
        ),
      ],
      activeScheme: 'test',
      autostartPomodoro: false,
      autostartBreak: false,
      finishSoundEnabled: false,
      tickingSound: false,
      notifications: false,
      notifyMinuteBefore: false,
      popupRaiseWindow: false,
      notifyTelegram: false,
    );
  }

  TimerCubit build({
    required Future<void> Function(PomodoroResult) onComplete,
  }) {
    return TimerCubit(
      settings: silentSettings,
      sound: SoundService(),
      notify: NotifyService(),
      store: _FakeStore(),
      hasTodos: () => true,
      onPomodoroComplete: onComplete,
    );
  }

  test('цикл: помидор → короткий → помидор → длинный, серия сбрасывается', () {
    fakeAsync((async) {
      final results = <PomodoroResult>[];
      final cubit = build(onComplete: (r) async => results.add(r));

      expect(cubit.state.mode, TimerMode.pomodoro);
      expect(cubit.state.remaining, 60);
      expect(cubit.state.stopped, isTrue);

      // Помидор №1.
      cubit.start();
      expect(cubit.state.running, isTrue);
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(results.length, 1);
      expect(results.first.workedMinutes, 1);
      expect(cubit.state.mode, TimerMode.shortBreak);
      expect(cubit.state.series, 1);
      expect(cubit.state.stopped, isTrue);

      // Короткий перерыв.
      cubit.start();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(cubit.state.mode, TimerMode.pomodoro);

      // Помидор №2 — после него длинный (каждые 2).
      cubit.start();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(results.length, 2);
      expect(cubit.state.mode, TimerMode.longBreak);
      expect(cubit.state.remaining, 120);

      // Длинный перерыв обнуляет серию.
      cubit.start();
      async.elapse(const Duration(seconds: 120));
      async.flushMicrotasks();
      expect(cubit.state.mode, TimerMode.pomodoro);
      expect(cubit.state.series, 0);

      cubit.close();
    });
  });

  test('пауза считает прерывания, резюм продолжает, DONE зачитывает факт', () {
    fakeAsync((async) {
      final results = <PomodoroResult>[];
      final cubit = build(onComplete: (r) async => results.add(r));

      cubit.start();
      async.elapse(const Duration(seconds: 20));
      cubit.pause();
      expect(cubit.state.paused, isTrue);
      expect(cubit.state.interruptions, 1);

      // Простой на паузе копится.
      final delaysBefore = cubit.state.delaysMs;
      async.elapse(const Duration(seconds: 5));
      expect(cubit.state.delaysMs, greaterThan(delaysBefore));

      cubit.resume();
      expect(cubit.state.running, isTrue);
      cubit.pause();
      expect(cubit.state.interruptions, 2);

      // Досрочное завершение с зачётом фактического времени.
      cubit.doneEarly();
      async.flushMicrotasks();
      expect(results.length, 1);
      expect(results.first.workedMinutes, 1); // ceil(20с−…/60) → 1 минимум
      expect(results.first.interruptions, 2);
      expect(cubit.state.mode, TimerMode.shortBreak);

      cubit.close();
    });
  });

  test('стоп сбрасывает фазу и счётчики, но не серию', () {
    fakeAsync((async) {
      final cubit = build(onComplete: (_) async {});
      cubit.start();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(cubit.state.series, 1);

      cubit.skipBreak();
      cubit.start();
      async.elapse(const Duration(seconds: 10));
      cubit.pause();
      cubit.resume();
      cubit.stop();
      expect(cubit.state.stopped, isTrue);
      expect(cubit.state.remaining, 60);
      expect(cubit.state.mode, TimerMode.pomodoro);
      expect(cubit.state.series, 1); // серия не тронута
      expect(cubit.state.interruptions, 0);
      expect(cubit.state.delaysMs, 0);
      cubit.close();
    });
  });

  test('пропуск перерыва и прокрутка фазы не пишут в историю', () {
    fakeAsync((async) {
      var completions = 0;
      final cubit = build(onComplete: (_) async => completions++);
      cubit.start();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(completions, 1);
      expect(cubit.state.mode, TimerMode.shortBreak);

      cubit.skipBreak();
      expect(cubit.state.mode, TimerMode.pomodoro);
      expect(cubit.state.series, 1);

      // Прокрутка помидора вперёд: серия растёт, записи нет.
      cubit.forward();
      expect(cubit.state.mode, TimerMode.longBreak);
      expect(cubit.state.series, 2);
      expect(completions, 1);
      cubit.close();
    });
  });

  test('продление добавляет минуты к текущей фазе', () {
    fakeAsync((async) {
      final cubit = build(onComplete: (_) async {});
      cubit.start();
      async.elapse(const Duration(seconds: 10));
      cubit.prolong();
      expect(cubit.state.remaining, 60 - 10 + 60);
      expect(cubit.state.total, 120);
      cubit.close();
    });
  });

  test('умный ввод разбирается на категорию, описание и помидоры', () {
    expect(parseSmartInput('#работа Код-ревью PR ~4'), (
      category: 'работа',
      description: 'Код-ревью PR',
      pomos: 4,
    ));
    expect(parseSmartInput('Просто текст ::2'), (
      category: null,
      description: 'Просто текст',
      pomos: 2,
    ));
    expect(parseSmartInput('Без всего'), (
      category: null,
      description: 'Без всего',
      pomos: null,
    ));
  });
}
