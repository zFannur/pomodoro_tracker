import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
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
    this.foreign = false,
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

  /// Помидор идёт на ДРУГОМ устройстве. Показываем его, но не завершаем и
  /// записи в журнал не делаем — иначе оба устройства записали бы один и тот
  /// же помидор дважды.
  final bool foreign;

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
    bool? foreign,
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
      foreign: foreign ?? this.foreign,
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
    foreign,
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

  /// Состояние таймера сменилось значимо (старт/пауза/стоп/смена фазы) —
  /// положить снимок в синхронизируемый документ. Периодические сохранения
  /// сюда НЕ идут: они бы дали по четыре аплоада в Drive на каждую минуту
  /// работающего помидора.
  Future<void> Function(Map<String, dynamic>? snap)? onTransition;

  /// Кто это устройство (см. AppSettings.deviceId).
  String Function()? deviceId;

  Timer? _ticker;
  Timer? _confirmTimer;
  DateTime? _startedAt;
  DateTime _stoppedAt = clock.now();
  int _sinceSave = 0;

  /// Момент, когда фаза должна закончиться. Отсчёт идёт от него, а не
  /// вычитанием единицы на тик: при сне машины или заморозке процесса на
  /// Android Timer.periodic схлопывает пропущенные тики в один, и помидор
  /// «на 25 минут» реально длился сорок пять.
  DateTime? _phaseEnd;

  /// Пересчитать остаток от настенных часов.
  int get _wallRemaining {
    final end = _phaseEnd;
    if (end == null) return state.remaining;
    final left = end.difference(clock.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

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
    final now = clock.now();
    final age = now.difference(saved.savedAt);
    if (age > const Duration(hours: 1)) return;
    // Часы могли уехать назад (NTP, ручная правка) — отрицательный возраст
    // давал remaining > total и отрицательный простой в журнале. Обнуляем
    // возраст, но состояние не выбрасываем: терять помидор из-за коррекции
    // часов на пару секунд — размен в минус.
    final elapsed = age.isNegative ? Duration.zero : age;
    final mode = TimerMode.values.asNameMap()[saved.mode] ?? TimerMode.pomodoro;
    final run = TimerRun.values.asNameMap()[saved.run] ?? TimerRun.stopped;
    if (run == TimerRun.running) {
      // Овертайм Flowtime проверяем ДО расчёта остатка: там remaining == 0,
      // и общий путь всегда уводил бы в ветку «дотикал».
      if (saved.overtime > 0) {
        _startedAt = saved.startedAt;
        _phaseEnd = saved.savedAt.subtract(Duration(seconds: saved.overtime));
        emit(
          TimerState(
            mode: mode,
            run: TimerRun.running,
            remaining: 0,
            total: saved.total,
            series: saved.series,
            interruptions: saved.interruptions,
            delaysMs: saved.delaysMs,
            overtime: saved.overtime + elapsed.inSeconds,
          ),
        );
        return;
      }
      final endtime = saved.savedAt.add(Duration(seconds: saved.remaining));
      final left = endtime.difference(now).inSeconds.clamp(0, saved.total);
      if (left > 1) {
        _startedAt =
            saved.startedAt ??
            now.subtract(Duration(seconds: saved.total - left));
        _phaseEnd = endtime;
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
      // Дотикал, пока приложение было закрыто. Раньше здесь фаза молча
      // выбрасывалась — отработанное время не попадало ни в журнал, ни в серию.
      _startedAt =
          saved.startedAt ?? endtime.subtract(Duration(seconds: saved.total));
      _phaseEnd = endtime;
      emit(
        TimerState(
          mode: mode,
          run: TimerRun.running,
          remaining: 0,
          total: saved.total,
          series: saved.series,
          interruptions: saved.interruptions,
          delaysMs: saved.delaysMs,
        ),
      );
      if (mode == TimerMode.pomodoro) {
        await _completePomodoro(workedSeconds: saved.total, silent: true);
      } else {
        _next();
        _save();
      }
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
          delaysMs: saved.delaysMs + elapsed.inMilliseconds,
          overtime: saved.overtime,
        ),
      );
      _startedAt = saved.startedAt;
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
    _claim();
    _ensureTicker();
    var series = state.series;
    // Простой дольше длинного перерыва сжигает серию.
    if (state.mode == TimerMode.pomodoro &&
        clock.now().difference(_stoppedAt).inSeconds >
            _settings().scheme.longBreak * 60) {
      series = 0;
    }
    _startedAt ??= clock.now().subtract(
      Duration(seconds: state.total - state.remaining),
    );
    _phaseEnd = clock.now().add(Duration(seconds: state.remaining));
    // Простой перед стартом остаётся накопленным — уйдёт в запись помидора.
    emit(state.copyWith(run: TimerRun.running, series: series));
    _save();
    _publish();
  }

  void pause() {
    if (!state.running) return;
    _claim();
    _phaseEnd = null;
    emit(
      state.copyWith(
        remaining: state.inOvertime ? state.remaining : _wallRemaining,
        run: TimerRun.paused,
        interruptions: state.mode == TimerMode.pomodoro
            ? state.interruptions + 1
            : state.interruptions,
      ),
    );
    _save();
    _publish();
  }

  void resume() {
    if (!state.paused) return;
    _claim();
    _phaseEnd = clock.now().add(Duration(seconds: state.remaining));
    emit(state.copyWith(run: TimerRun.running));
    _save();
    _publish();
  }

  /// СТОП: сброс текущей фазы к началу; режим и серия не меняются.
  void stop() {
    _claim();
    _startedAt = null;
    _phaseEnd = null;
    _stoppedAt = clock.now();
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
    _publish();
  }

  /// Продлить текущую фазу (по умолчанию на 1 минуту, Shift — на 5).
  void prolong([int minutes = 1]) {
    final end = _phaseEnd;
    if (end != null) _phaseEnd = end.add(Duration(minutes: minutes));
    emit(
      state.copyWith(
        remaining: state.remaining + minutes * 60,
        total: state.total + minutes * 60,
      ),
    );
    // Без записи снимка продление терялось при убийстве процесса, и помидор
    // заканчивался на N минут раньше, чем рассчитывал пользователь.
    _save();
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
      final end = _phaseEnd;
      final grown = end == null
          ? state.overtime + 1
          : clock.now().difference(end).inSeconds;
      emit(state.copyWith(overtime: grown < 1 ? 1 : grown));
      _periodicSave();
      return;
    }
    final remaining = _wallRemaining;
    if (remaining <= 0) {
      // Чужой помидор дотикал — просто гасим показ. Запись сделает то
      // устройство, на котором он шёл.
      if (state.foreign) {
        _phaseEnd = null;
        emit(state.copyWith(run: TimerRun.stopped, foreign: false));
        return;
      }
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

  Future<void> _completePomodoro({
    required int workedSeconds,
    bool silent = false,
  }) async {
    final settings = _settings();
    final result = PomodoroResult(
      workedMinutes: math.max(1, (workedSeconds / 60).ceil()),
      delayMs: state.delaysMs,
      interruptions: state.interruptions,
      startedAt:
          _startedAt ?? clock.now().subtract(Duration(seconds: workedSeconds)),
    );
    // silent — помидор дотикал, пока приложения не было: запись нужна,
    // звонок через час после факта — нет.
    if (settings.finishSoundEnabled && !silent) {
      unawaited(_sound.playFinish(settings.finishSound, settings.volume));
    }
    final nextIsLong = state.series + 1 >= settings.scheme.longEvery;
    if (!silent) {
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
    }
    _next();
    if (settings.autostartBreak && !silent) start();
    _save();
    _publish();
    await _onPomodoroComplete(result);
  }

  /// Переход фазы: помидор → перерыв (серия++), перерыв → помидор
  /// (после длинного серия сбрасывается).
  void _next() {
    _startedAt = null;
    _phaseEnd = null;
    _stoppedAt = clock.now();
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

  /// Снимок для синка: чужому устройству хватит конца фазы и длительности —
  /// остаток оно досчитает по своим настенным часам.
  void _publish() {
    final publish = onTransition;
    if (publish == null || state.foreign) return;
    if (state.stopped) {
      unawaited(publish(null));
      return;
    }
    unawaited(
      publish({
        'device': deviceId?.call() ?? '',
        'savedAt': clock.now().millisecondsSinceEpoch,
        'mode': state.mode.name,
        'run': state.run.name,
        'remaining': state.remaining,
        'total': state.total,
        'overtime': state.overtime,
        if (_phaseEnd != null) 'endsAt': _phaseEnd!.millisecondsSinceEpoch,
      }),
    );
  }

  /// Синк принёс снимок таймера. Свой игнорируем, чужой показываем — но
  /// только когда здесь ничего не идёт: перебивать локальный помидор нельзя.
  void adoptRemote(Map<String, dynamic>? snap) {
    if (snap == null) {
      if (state.foreign) {
        _phaseEnd = null;
        emit(state.copyWith(run: TimerRun.stopped, foreign: false));
      }
      return;
    }
    if (snap['device'] == (deviceId?.call() ?? '')) return;
    if (!state.stopped && !state.foreign) return;
    final mode =
        TimerMode.values.asNameMap()[snap['mode']] ?? TimerMode.pomodoro;
    final run = TimerRun.values.asNameMap()[snap['run']] ?? TimerRun.stopped;
    final total = (snap['total'] as num?)?.toInt() ?? _modeSeconds(mode);
    final ends = snap['endsAt'];
    _phaseEnd = ends is int ? DateTime.fromMillisecondsSinceEpoch(ends) : null;
    final left = run == TimerRun.running
        ? _wallRemaining
        : (snap['remaining'] as num?)?.toInt() ?? total;
    emit(
      TimerState(
        mode: mode,
        run: run,
        remaining: left.clamp(0, total),
        total: total,
        series: state.series,
        interruptions: 0,
        delaysMs: 0,
        overtime: (snap['overtime'] as num?)?.toInt() ?? 0,
        foreign: true,
      ),
    );
  }

  /// Взять управление себе: любое локальное действие снимает «чужой».
  void _claim() {
    if (state.foreign) emit(state.copyWith(foreign: false));
  }

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
          overtime: state.overtime,
          startedAt: _startedAt,
          savedAt: clock.now(),
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
