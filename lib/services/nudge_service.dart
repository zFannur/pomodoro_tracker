import 'dart:async';

import 'package:clock/clock.dart';

import '../app/strings.dart';
import '../data/markdown_codec.dart' show dateKey;
import '../domain/entities/app_settings.dart';
import '../domain/entities/pomo_session.dart' show logicalDate;
import '../domain/entities/pomo_task.dart';
import '../presentation/cubits/timer_cubit.dart';
import 'notify_service.dart';

bool shouldNudgeIdle({
  required bool enabled,
  required bool stoppedPomodoro,
  required bool foreign,
  required bool hasTodos,
  required int delayMs,
  required int? inputIdleSeconds,
  required bool inWindow,
  required bool alreadyNudged,
}) =>
    enabled &&
    stoppedPomodoro &&
    !foreign &&
    hasTodos &&
    delayMs >= const Duration(minutes: 15).inMilliseconds &&
    inputIdleSeconds != null &&
    inputIdleSeconds >= 0 &&
    inputIdleSeconds <= 60 &&
    inWindow &&
    !alreadyNudged;

String cueKey(PomoTask task, DateTime now) =>
    '${task.id}@${dateKey(logicalDate(now))}';

List<PomoTask> dueCues(List<PomoTask> todo, DateTime now, Set<String> fired) {
  final minute =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
  return [
    for (final task in todo)
      if (task.id != null &&
          task.id!.isNotEmpty &&
          task.cueAt == minute &&
          !fired.contains(cueKey(task, now)))
        task,
  ];
}

bool inSessionWindow(List<String> windows, DateTime now) {
  if (windows.isEmpty) return true;
  final minute = now.hour * 60 + now.minute;
  return parseSessionWindows(
    windows,
  ).any((window) => minute >= window.start && minute < window.end);
}

/// Один опрос для простоя и «когда»; пропущенные минуты не догоняем.
class NudgeService {
  NudgeService({
    required this.settings,
    required this.timerState,
    required this.timerChanges,
    required this.todos,
    required this.inputIdleSeconds,
    required this.notify,
    required this.onIdle,
  });

  final AppSettings Function() settings;
  final TimerState Function() timerState;
  final Stream<TimerState> timerChanges;
  final List<PomoTask> Function() todos;
  final int? Function() inputIdleSeconds;
  final NotifyService notify;
  final Future<void> Function(PomoTask task) onIdle;

  Timer? _timer;
  StreamSubscription<TimerState>? _subscription;
  final _fired = <String>{};
  int _lastDelay = 0;
  bool _alreadyNudged = false;
  bool _busy = false;
  bool _disposed = false;

  void start() {
    if (_timer != null || _disposed) return;
    _lastDelay = timerState().delaysMs;
    // Старт и быстрый стоп между двумя опросами тоже заканчивают простой.
    _subscription = timerChanges.listen(_observeTimer);
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(tick()),
    );
  }

  void _observeTimer(TimerState state) {
    if (state.delaysMs < _lastDelay || state.running) _alreadyNudged = false;
    _lastDelay = state.delaysMs;
  }

  Future<void> tick() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final now = clock.now();
      final currentSettings = settings();
      final state = timerState();
      _observeTimer(state);
      final tasks = todos();
      if (shouldNudgeIdle(
        enabled: currentSettings.nudgeIdle,
        stoppedPomodoro: state.mode == TimerMode.pomodoro && state.stopped,
        foreign: state.foreign,
        hasTodos: tasks.isNotEmpty,
        delayMs: state.delaysMs,
        inputIdleSeconds: inputIdleSeconds(),
        inWindow: inSessionWindow(currentSettings.sessionWindows, now),
        alreadyNudged: _alreadyNudged,
      )) {
        _alreadyNudged = true;
        final task = tasks.first;
        await onIdle(task);
        if (_disposed) return;
        await notify.event(
          currentSettings,
          title: S.nudgeIdleTitle,
          body: S.nudgeIdleBody(task.description),
          raise: false,
        );
      }
      if (_disposed) return;
      final suffix = '@${dateKey(logicalDate(now))}';
      _fired.removeWhere((key) => !key.endsWith(suffix));
      for (final task in dueCues(tasks, now, _fired)) {
        _fired.add(cueKey(task, now));
        await notify.event(
          currentSettings,
          title: S.cueTitle,
          body: S.cueBody(
            task.cue,
            task.firstStep.isEmpty ? task.description : task.firstStep,
          ),
          raise: false,
        );
        if (_disposed) return;
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
  }
}
