import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/nudge_service.dart';

class _Notify extends NotifyService {
  final events = <({String title, String body, bool raise})>[];
  @override
  Future<void> event(
    AppSettings settings, {
    required String title,
    required String body,
    bool raise = false,
  }) async {
    events.add((title: title, body: body, raise: raise));
  }
}

TimerState timer({int delay = 900000, TimerRun run = TimerRun.stopped}) =>
    TimerState(
      mode: TimerMode.pomodoro,
      run: run,
      remaining: 1500,
      total: 1500,
      series: 0,
      interruptions: 0,
      delaysMs: delay,
    );

void main() {
  bool should({
    bool enabled = true,
    bool stopped = true,
    bool foreign = false,
    bool hasTodos = true,
    int delay = 900000,
    int? input = 60,
    bool window = true,
    bool nudged = false,
  }) => shouldNudgeIdle(
    enabled: enabled,
    stoppedPomodoro: stopped,
    foreign: foreign,
    hasTodos: hasTodos,
    delayMs: delay,
    inputIdleSeconds: input,
    inWindow: window,
    alreadyNudged: nudged,
  );

  test('простой: все условия и точные границы', () {
    expect(should(), isTrue);
    expect(should(input: 0), isTrue);
  });
  final cases = <String, bool Function()>{
    'выключено': () => should(enabled: false),
    'не остановленный помидор': () => should(stopped: false),
    'чужой таймер': () => should(foreign: true),
    'нет задач': () => should(hasTodos: false),
    'меньше 15 минут': () => should(delay: 899999),
    'Android без ввода': () => should(input: null),
    'нет свежего ввода': () => should(input: 61),
    'отрицательный ввод': () => should(input: -1),
    'вне окна': () => should(window: false),
    'уже сообщали': () => should(nudged: true),
  };
  for (final entry in cases.entries) {
    test('простой: ${entry.key}', () => expect(entry.value(), isFalse));
  }

  test('окна: пусто, границы, несколько окон, битое расписание', () {
    final now = DateTime(2026, 11, 4, 10);
    expect(inSessionWindow([], now), isTrue);
    expect(inSessionWindow(['10:00-11:00'], now), isTrue);
    expect(inSessionWindow(['09:00-10:00'], now), isFalse);
    expect(inSessionWindow(['08:00-09:00', '10:00-11:00'], now), isTrue);
    expect(inSessionWindow(['bad'], now), isFalse);
  });

  const task = PomoTask(
    id: 'task',
    description: 'задача',
    category: 'x',
    durationMinutes: 25,
    cue: 'после кофе',
    firstStep: 'открыть файл',
    cueAt: '00:30',
  );
  test('dueCues: минута, повтор, новая логическая дата и невалидный id', () {
    final now = DateTime(2026, 11, 5, 0, 30);
    final fired = <String>{};
    expect(dueCues([task], now, fired), [task]);
    expect(cueKey(task, now), 'task@2026-11-04');
    fired.add(cueKey(task, now));
    expect(
      dueCues([task], now.add(const Duration(seconds: 30)), fired),
      isEmpty,
    );
    expect(dueCues([task], now.add(const Duration(days: 1)), fired), [task]);
    expect(dueCues([task], now.add(const Duration(minutes: 1)), {}), isEmpty);
    expect(dueCues([task.copyWith(cueAt: '')], now, {}), isEmpty);
    expect(dueCues([task.copyWith(id: '')], now, {}), isEmpty);
  });

  test(
    'сервис: один сигнал на простой, сброс по уменьшению и быстрому старту',
    () {
      fakeAsync((async) {
        var state = timer();
        final changes = StreamController<TimerState>.broadcast(sync: true);
        final notify = _Notify();
        var episodes = 0;
        final service = NudgeService(
          settings: () => AppSettings.fromJson(const {}, fallbackPath: '.'),
          timerState: () => state,
          timerChanges: changes.stream,
          todos: () => [task],
          inputIdleSeconds: () => 0,
          notify: notify,
          onIdle: (t) async {
            expect(t, task);
            episodes++;
          },
        )..start();
        service.start();
        async.elapse(const Duration(minutes: 2));
        expect(episodes, 1);
        expect(notify.events.single.title, S.nudgeIdleTitle);
        expect(notify.events.single.body, S.nudgeIdleBody(task.description));
        expect(notify.events.single.raise, isFalse);
        state = timer(delay: 0);
        changes.add(state);
        state = timer();
        changes.add(state);
        async.elapse(const Duration(seconds: 30));
        expect(episodes, 2);
        state = timer(run: TimerRun.running);
        changes.add(state);
        state = timer();
        changes.add(state);
        async.elapse(const Duration(seconds: 30));
        expect(episodes, 3);
        unawaited(service.dispose());
        unawaited(changes.close());
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 2));
        expect(episodes, 3);
        expect(async.periodicTimerCount, 0);
      }, initialTime: DateTime(2026, 11, 4, 10));
    },
  );

  test(
    'сервис: Android не создаёт idle; cue один раз и fallback описания',
    () => withClock(Clock.fixed(DateTime(2026, 11, 5, 0, 30)), () async {
      final changes = StreamController<TimerState>.broadcast();
      final notify = _Notify();
      var idle = 0;
      final service = NudgeService(
        settings: () => AppSettings.fromJson(const {}, fallbackPath: '.'),
        timerState: timer,
        timerChanges: changes.stream,
        todos: () => [task, task.copyWith(id: 'other', firstStep: '')],
        inputIdleSeconds: () => null,
        notify: notify,
        onIdle: (_) async {
          idle++;
        },
      );
      await service.tick();
      await service.tick();
      expect(idle, 0);
      expect(notify.events, hasLength(2));
      expect(notify.events.first.body, S.cueBody(task.cue, task.firstStep));
      expect(notify.events.last.body, S.cueBody(task.cue, task.description));
      expect(notify.events.every((e) => !e.raise), isTrue);
      await service.dispose();
      await changes.close();
    }),
  );

  test('новые настройки: старый JSON, copyWith, props и round-trip', () {
    final old = AppSettings.fromJson(const {}, fallbackPath: '.');
    expect(old.nudgeIdle, isTrue);
    expect(old.nudgeDistraction, isTrue);
    final changed = old.copyWith(nudgeIdle: false, nudgeDistraction: false);
    expect(changed, isNot(old));
    expect(old.copyWith(nudgeIdle: false), isNot(old));
    expect(old.copyWith(nudgeDistraction: false), isNot(old));
    expect(AppSettings.fromJson(changed.toJson(), fallbackPath: '.'), changed);
  });
}
