import 'dart:async';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/timer_state_store.dart';
import '../../domain/entities/app_settings.dart';
import '../../services/notify_service.dart';
import '../../services/sound_service.dart';

enum TimerMode { pomodoro, shortBreak, longBreak }

enum TimerRun { stopped, running, paused }

/// Данные завершённого помидора для записи в историю.
class PomodoroResult {
  const PomodoroResult({
    required this.workedMinutes,
    required this.delayMs,
    required this.interruptions,
    required this.startedAt,
  });

  final int workedMinutes;
  final int delayMs;
  final int interruptions;
  final DateTime startedAt;
}

class TimerState extends Equatable {
  const TimerState({
    required this.mode,
    required this.run,
    required this.remaining,
    required this.total,
    required this.series,
    required this.interruptions,
    required this.delaysMs,
    this.overtime = 0,
    this.confirmArmed = false,
  });

  final TimerMode mode;
  final TimerRun run;

  /// Осталось секунд.
  final int remaining;

  /// Полная длительность фазы в секундах (с учётом продлений).
  final int total;

  /// Завершено помидоров в текущей серии (до длинного перерыва).
  final int series;

  /// Пауз в текущем помидоре.
  final int interruptions;

  /// Накопленный простой, мс (пока таймер стоит или на паузе).
  final int delaysMs;

  /// Flowtime: секунды сверх помидора (0 — обычный режим).
  final int overtime;

  /// Первый Esc нажат — кнопка показывает «?» 1.5 секунды.
  final bool confirmArmed;

  bool get inOvertime => overtime > 0;

  bool get isBreak => mode != TimerMode.pomodoro;

  bool get running => run == TimerRun.running;

  bool get paused => run == TimerRun.paused;

  bool get stopped => run == TimerRun.stopped;

  TimerState copyWith({
    TimerMode? mode,
    TimerRun? run,
    int? remaining,
    int? total,
    int? series,
    int? interruptions,
    int? delaysMs,
    int? overtime,
    bool? confirmArmed,
  }) {
    return TimerState(
      mode: mode ?? this.mode,
      run: run ?? this.run,
      remaining: remaining ?? this.remaining,
      total: total ?? this.total,
      series: series ?? this.series,
      interruptions: interruptions ?? this.interruptions,
      delaysMs: delaysMs ?? this.delaysMs,
      overtime: overtime ?? this.overtime,
      confirmArmed: confirmArmed ?? this.confirmArmed,
    );
  }

  @override
  List<Object?> get props => [
    mode,
    run,
    remaining,
    total,
    series,
    interruptions,
    delaysMs,
    overtime,
    confirmArmed,
  ];
}

/// Цикл помидор → перерыв c семантикой оригинала: серия, пауза с
/// прерываниями, накопление простоя, продление, персистентность.
class TimerCubit extends Cubit<TimerState> {
  TimerCubit({
    required this._settings,
    required this._sound,
    required this._notify,
    required this._store,
    required this._hasTodos,
    required this._onPomodoroComplete,
  }) : super(
         TimerState(
           mode: TimerMode.pomodoro,
           run: TimerRun.stopped,
           remaining: _settings().scheme.pomodoro * 60,
           total: _settings().scheme.pomodoro * 60,
           series: 0,
           interruptions: 0,
           delaysMs: 0,
         ),
       );

  final AppSettings Function() _settings;
  final SoundService _sound;
  final NotifyService _notify;
  final TimerStateStore _store;
  final bool Function() _hasTodos;
  final Future<void> Function(PomodoroResult result) _onPomodoroComplete;

  Timer? _ticker;
  Timer? _confirmTimer;
  DateTime? _startedAt;
  DateTime _stoppedAt = DateTime.now();
  int _sinceSave = 0;

  int _modeSeconds(TimerMode mode) {
    final scheme = _settings().scheme;
    return switch (mode) {
      TimerMode.pomodoro => scheme.pomodoro * 60,
      TimerMode.shortBreak => scheme.shortBreak * 60,
      TimerMode.longBreak => scheme.longBreak * 60,
    };
  }

  /// Восстановление после перезапуска: бегущий таймер продолжает идти,
  /// пауза и серия переживают перезапуск в пределах часа.
  Future<void> restore() async {
    final saved = await _store.load();
    _ensureTicker();
    if (saved == null) return;
    final now = DateTime.now();
    final age = now.difference(saved.savedAt);
    if (age > const Duration(hours: 1)) return;
    final mode = TimerMode.values.asNameMap()[saved.mode] ?? TimerMode.pomodoro;
    final run = TimerRun.values.asNameMap()[saved.run] ?? TimerRun.stopped;
    if (run == TimerRun.running) {
      final endtime = saved.savedAt.add(Duration(seconds: saved.remaining));
      final left = endtime.difference(now).inSeconds;
      if (left > 1) {
        _startedAt = now.subtract(Duration(seconds: saved.total - left));
        emit(
          TimerState(
            mode: mode,
            run: TimerRun.running,
            remaining: left,
            total: saved.total,
            series: saved.series,
            interruptions: saved.interruptions,
            delaysMs: saved.delaysMs,
          ),
        );
        return;
      }
      // Дотикал, пока приложение было закрыто, — считаем фазу завершённой
      // без записи (запись требует живого списка задач на момент финиша).
      emit(state.copyWith(series: saved.series));
      return;
    }
    if (run == TimerRun.paused) {
      emit(
        TimerState(
          mode: mode,
          run: TimerRun.paused,
          remaining: saved.remaining,
          total: saved.total,
          series: saved.series,
          interruptions: saved.interruptions,
          delaysMs: saved.delaysMs + age.inMilliseconds,
        ),
      );
      return;
    }
    // Остановленный таймер: в пределах часа переживает только серия.
    emit(state.copyWith(series: saved.series));
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // -- управление -----------------------------------------------------------

  /// Space: стоп → старт; пауза → резюм; бег → пауза.
  void spacePressed() {
    switch (state.run) {
      case TimerRun.stopped:
        start();
      case TimerRun.paused:
        resume();
      case TimerRun.running:
        pause();
    }
  }

  /// Esc: первый — взвести подтверждение, второй за 1.5 c — стоп/скип.
  void escPressed() {
    if (state.stopped) return;
    if (!state.confirmArmed) {
      emit(state.copyWith(confirmArmed: true));
      _confirmTimer?.cancel();
      _confirmTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!isClosed) emit(state.copyWith(confirmArmed: false));
      });
      return;
    }
    _confirmTimer?.cancel();
    emit(state.copyWith(confirmArmed: false));
    if (state.isBreak) {
      skipBreak();
    } else {
      stop();
    }
  }

  void start() {
    if (state.running) return;
    _ensureTicker();
    var series = state.series;
    // Простой дольше длинного перерыва сжигает серию.
    if (state.mode == TimerMode.pomodoro &&
        DateTime.now().difference(_stoppedAt).inSeconds >
            _settings().scheme.longBreak * 60) {
      series = 0;
    }
    _startedAt ??= DateTime.now().subtract(
      Duration(seconds: state.total - state.remaining),
    );
    // Простой перед стартом остаётся накопленным — уйдёт в запись помидора.
    emit(state.copyWith(run: TimerRun.running, series: series));
    _save();
  }

  void pause() {
    if (!state.running) return;
    emit(
      state.copyWith(
        run: TimerRun.paused,
        interruptions: state.mode == TimerMode.pomodoro
            ? state.interruptions + 1
            : state.interruptions,
      ),
    );
    _save();
  }

  void resume() {
    if (!state.paused) return;
    emit(state.copyWith(run: TimerRun.running));
    _save();
  }

  /// СТОП: сброс текущей фазы к началу; режим и серия не меняются.
  void stop() {
    _startedAt = null;
    _stoppedAt = DateTime.now();
    final seconds = _modeSeconds(state.mode);
    emit(
      state.copyWith(
        run: TimerRun.stopped,
        remaining: seconds,
        total: seconds,
        delaysMs: 0,
        interruptions: 0,
        overtime: 0,
      ),
    );
    _save();
  }

  /// Продлить текущую фазу (по умолчанию на 1 минуту, Shift — на 5).
  void prolong([int minutes = 1]) {
    emit(
      state.copyWith(
        remaining: state.remaining + minutes * 60,
        total: state.total + minutes * 60,
      ),
    );
  }

  /// Прокрутить фазу вперёд без запуска (стрелка при остановленном таймере).
  /// Прокрутка помидора увеличивает серию, но записи не создаёт.
  void forward() {
    if (!state.stopped) return;
    _next();
    _save();
  }

  /// Пропустить перерыв — сразу к следующему помидору.
  void skipBreak() {
    if (!state.isBreak) return;
    _next();
    _maybeAutostartPomodoro();
    _save();
  }

  /// Завершить помидор досрочно (кнопка DONE на паузе) либо закрыть
  /// овертайм Flowtime — с зачётом фактически отработанного времени.
  Future<void> doneEarly() async {
    if (state.mode != TimerMode.pomodoro) return;
    if (state.inOvertime) {
      await _completePomodoro(workedSeconds: state.total + state.overtime);
      return;
    }
    if (!state.paused) return;
    await _completePomodoro(workedSeconds: state.total - state.remaining);
  }

  /// Применить изменившуюся схему, если таймер стоит.
  void applySchemeIfIdle() {
    if (!state.stopped) return;
    final seconds = _modeSeconds(state.mode);
    if (state.total != seconds) {
      emit(state.copyWith(remaining: seconds, total: seconds));
    }
  }

  // -- тик и завершение фаз --------------------------------------------------

  void _tick() {
    final settings = _settings();
    if (!state.running) {
      // Простой копится, пока таймер стоит или на паузе.
      emit(state.copyWith(delaysMs: state.delaysMs + 1000));
      _periodicSave();
      return;
    }
    // Flowtime: помидор дотикал — тихо считаем вверх, поток не выбиваем.
    if (state.inOvertime) {
      emit(state.copyWith(overtime: state.overtime + 1));
      _periodicSave();
      return;
    }
    final remaining = state.remaining - 1;
    if (remaining <= 0) {
      if (settings.flowtime && state.mode == TimerMode.pomodoro) {
        emit(state.copyWith(remaining: 0, overtime: 1));
        return;
      }
      _finishPhase();
      return;
    }
    final tickInPomodoro =
        settings.tickingSound && state.mode == TimerMode.pomodoro;
    final tickInBreak = settings.tickingInBreaks && state.isBreak;
    if (tickInPomodoro || tickInBreak) {
      unawaited(_sound.playTick(settings.volume));
    }
    if (remaining == 60 && settings.notifyMinuteBefore) {
      unawaited(
        _notify.event(
          settings,
          title: S.notifyMinuteLeft,
          body: state.isBreak ? S.breakWord : S.pomodoroWord,
        ),
      );
    }
    emit(state.copyWith(remaining: remaining));
    _periodicSave();
  }

  void _finishPhase() {
    if (state.mode == TimerMode.pomodoro) {
      unawaited(_completePomodoro(workedSeconds: state.total));
    } else {
      final settings = _settings();
      if (settings.finishSoundEnabled) {
        unawaited(_sound.playFinish(settings.finishSound, settings.volume));
      }
      unawaited(
        _notify.event(
          settings,
          title: S.notifyBreakDone,
          body: _notify.pickMessage(
            settings.msgBreakDone,
            S.notifyBreakDoneBody,
          ),
          raise: true,
        ),
      );
      _next();
      _maybeAutostartPomodoro();
      _save();
    }
  }

  Future<void> _completePomodoro({required int workedSeconds}) async {
    final settings = _settings();
    final result = PomodoroResult(
      workedMinutes: math.max(1, (workedSeconds / 60).ceil()),
      delayMs: state.delaysMs,
      interruptions: state.interruptions,
      startedAt:
          _startedAt ??
          DateTime.now().subtract(Duration(seconds: workedSeconds)),
    );
    if (settings.finishSoundEnabled) {
      unawaited(_sound.playFinish(settings.finishSound, settings.volume));
    }
    final nextIsLong = state.series + 1 >= settings.scheme.longEvery;
    unawaited(
      _notify.event(
        settings,
        title: S.notifyPomodoroDone,
        body: _notify.pickMessage(
          settings.msgPomodoroDone,
          nextIsLong ? S.takeLongBreak : S.takeShortBreak,
        ),
        raise: true,
      ),
    );
    _next();
    if (settings.autostartBreak) start();
    _save();
    await _onPomodoroComplete(result);
  }

  /// Переход фазы: помидор → перерыв (серия++), перерыв → помидор
  /// (после длинного серия сбрасывается).
  void _next() {
    _startedAt = null;
    _stoppedAt = DateTime.now();
    final settings = _settings();
    TimerMode mode;
    var series = state.series;
    if (state.mode == TimerMode.pomodoro) {
      series += 1;
      mode = series >= settings.scheme.longEvery
          ? TimerMode.longBreak
          : TimerMode.shortBreak;
    } else {
      if (state.mode == TimerMode.longBreak) series = 0;
      mode = TimerMode.pomodoro;
    }
    final seconds = _modeSeconds(mode);
    emit(
      TimerState(
        mode: mode,
        run: TimerRun.stopped,
        remaining: seconds,
        total: seconds,
        series: series,
        interruptions: 0,
        delaysMs: 0,
      ),
    );
  }

  void _maybeAutostartPomodoro() {
    final settings = _settings();
    if (!settings.autostartPomodoro) return;
    if (settings.autostartIfTodo && !_hasTodos()) return;
    start();
  }

  // -- персистентность -------------------------------------------------------

  void _periodicSave() {
    _sinceSave += 1;
    if (_sinceSave >= 15) _save();
  }

  void _save() {
    _sinceSave = 0;
    unawaited(
      _store.save(
        TimerSnapshot(
          mode: state.mode.name,
          run: state.run.name,
          remaining: state.remaining,
          total: state.total,
          series: state.series,
          interruptions: state.interruptions,
          delaysMs: state.delaysMs,
          savedAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    _confirmTimer?.cancel();
    return super.close();
  }
}
