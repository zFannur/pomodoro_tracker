import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/failure.dart';
import '../../data/json_data_repository.dart' show newId;
import '../../data/markdown_codec.dart' show mondayOfSprintId, sprintId;
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/experiment.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/entities/sprint.dart';
import '../../domain/insights.dart';
import '../../domain/repositories.dart';
import '../../domain/strategies.dart';

enum InsightStatus { loading, ready, failure }

class InsightState extends Equatable {
  const InsightState({
    required this.status,
    this.days = const [],
    this.sprint,
    this.previous,
    this.lastDeferral,
    this.error = '',
  });

  final InsightStatus status;
  final List<DayLog> days;
  final Sprint? sprint;
  final Sprint? previous;
  final ({Episode episode, int count})? lastDeferral;
  final String error;

  InsightState copyWith({
    InsightStatus? status,
    List<DayLog>? days,
    Sprint? sprint,
    Sprint? previous,
    bool clearPrevious = false,
    ({Episode episode, int count})? lastDeferral,
    String? error,
  }) => InsightState(
    status: status ?? this.status,
    days: days ?? this.days,
    sprint: sprint ?? this.sprint,
    previous: clearPrevious ? null : previous ?? this.previous,
    lastDeferral: lastDeferral ?? this.lastDeferral,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [
    status,
    days,
    sprint,
    previous,
    lastDeferral,
    error,
  ];
}

class InsightCubit extends Cubit<InsightState> {
  InsightCubit(
    this._insights,
    this._journal,
    this._sprints,
    this._settings, {
    this.distractPercent,
  }) : super(const InsightState(status: InsightStatus.loading));

  final InsightRepository _insights;
  final JournalRepository _journal;
  final SprintRepository _sprints;
  final AppSettings Function() _settings;
  final double? Function(DateTime from, DateTime to)? distractPercent;

  Future<void> refresh() async {
    final date = logicalDate(clock.now());
    final from = DateTime(date.year, date.month, date.day - 181);
    final daysResult = await _journal.range(from, date, _settings().dailyGoal);
    final failure = daysResult.fold((e) => e, (_) => null);
    if (failure != null) return _fail(failure);
    final sprintResult = await _sprints.current(date, _settings().sprintGoal);
    final sprintFailure = sprintResult.fold((e) => e, (_) => null);
    if (sprintFailure != null) return _fail(sprintFailure);
    final sprint = sprintResult.getOrElse((_) => throw StateError('sprint'));
    final previousDate = DateTime(date.year, date.month, date.day - 7);
    final historyResult = await _sprints.history();
    final historyFailure = historyResult.fold((e) => e, (_) => null);
    if (historyFailure != null) return _fail(historyFailure);
    Sprint? previous;
    if (historyResult
        .getOrElse((_) => [])
        .any((s) => s.id == sprintId(previousDate))) {
      final result = await _sprints.current(
        previousDate,
        _settings().sprintGoal,
      );
      final error = result.fold((e) => e, (_) => null);
      if (error != null) return _fail(error);
      previous = result.getOrElse((_) => throw StateError('previous'));
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        status: InsightStatus.ready,
        error: '',
        days: daysResult.getOrElse((_) => []),
        sprint: sprint,
        previous: previous,
        clearPrevious: previous == null,
      ),
    );
  }

  void _fail(Failure failure) {
    if (!isClosed) {
      emit(
        state.copyWith(status: InsightStatus.failure, error: failure.message),
      );
    }
  }

  DayLog _day(DateTime date) =>
      state.days.where((d) => d.date == date).firstOrNull ??
      DayLog(date: date, goal: _settings().dailyGoal, sessions: const []);
  DayLog get today => _day(logicalDate(clock.now()));
  DayLog get yesterday {
    final d = logicalDate(clock.now());
    return _day(DateTime(d.year, d.month, d.day - 1));
  }

  List<Episode> get todayEpisodes => today.episodes;
  CheckIn get checkIn => today.checkIn;
  String? get baselineWeekId => baselineWeek(state.days);
  bool get observation =>
      isObservationWeek(sprintId(logicalDate(clock.now())), baselineWeekId);
  Experiment? get experiment => state.sprint?.experiment;
  Map<StrategyKind, ({int tries, int wins})> get stats =>
      strategyStats(state.days);
  List<StrategyKind> ranked(Cause c) =>
      rankFor(c, stats, pinned: experiment?.strategy);

  WeekInsight _week(DateTime monday) {
    final end = DateTime(monday.year, monday.month, monday.day + 7);
    return weekInsight(
      state.days
          .where((d) => !d.date.isBefore(monday) && d.date.isBefore(end))
          .toList(),
      windows: parseSessionWindows(_settings().sessionWindows),
      distractPercent: distractPercent?.call(
        monday.add(const Duration(hours: dayStartHour)),
        end.add(const Duration(hours: dayStartHour)),
      ),
    );
  }

  DateTime get _monday {
    final d = logicalDate(clock.now());
    return DateTime(d.year, d.month, d.day - d.weekday + 1);
  }

  WeekInsight get current => _week(_monday);
  WeekInsight get previousWeek {
    final d = _monday;
    return _week(DateTime(d.year, d.month, d.day - 7));
  }

  WeekInsight? get baselineInsight {
    final id = baselineWeekId;
    final monday = id == null ? null : mondayOfSprintId(id);
    return monday == null ? null : _week(monday);
  }

  /// Обезличенный вход недельного разбора ИИ (см. [reviewPayload]).
  Map<String, Object?> aiPayload() => reviewPayload(
    week: sprintId(logicalDate(clock.now())),
    observation: observation,
    monday: _monday,
    current: current,
    previous: previousWeek,
    baseline: observation ? null : baselineInsight,
    days: state.days,
    windows: parseSessionWindows(_settings().sessionWindows),
    experiment: experiment,
    lastExperiment: state.previous?.experiment,
  );

  Episode? pendingEpisode(EpisodeSource source) {
    final now = clock.now();
    Episode? latest;
    for (final e in todayEpisodes) {
      if (e.source != source ||
          e.cause != null ||
          e.at.isAfter(now) ||
          now.difference(e.at) > const Duration(minutes: 60)) {
        continue;
      }
      if (latest == null || e.at.isAfter(latest.at)) latest = e;
    }
    return latest;
  }

  Future<void> _write(Future<Either<Failure, Unit>> operation) async {
    final result = await operation;
    final failure = result.fold((e) => e, (_) => null);
    if (failure != null) {
      _fail(failure);
      return;
    }
    await refresh();
  }

  Future<Episode> addEpisode({
    required EpisodeSource source,
    PomoTask? task,
    String app = '',
    Cause? cause,
    String thought = '',
    DateTime? at,
  }) async {
    final e = Episode(
      id: newId(),
      at: at ?? clock.now(),
      source: source,
      taskId: task?.id ?? '',
      task: task?.description ?? '',
      category: task?.category ?? '',
      app: app,
      cause: cause,
      thought: thought,
    );
    await _write(_insights.addEpisode(e));
    return e;
  }

  Episode? _episode(String id) {
    for (final day in state.days) {
      for (final e in day.episodes) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  Future<void> setCause(String id, Cause c, {String thought = ''}) async {
    final e = _episode(id);
    if (e != null) {
      await _write(
        _insights.updateEpisode(e.copyWith(cause: c, thought: thought)),
      );
    }
  }

  Future<void> setStrategy(
    String id,
    StrategyKind k, {
    String fact = '',
    String alt = '',
  }) async {
    final e = _episode(id);
    if (e != null) {
      await _write(
        _insights.updateEpisode(e.copyWith(strategy: k, fact: fact, alt: alt)),
      );
    }
  }

  Future<void> deleteEpisode(String id) => _write(_insights.deleteEpisode(id));
  Future<void> setCheckIn(CheckIn ck) =>
      _write(_insights.setCheckIn(logicalDate(clock.now()), ck));
  Future<void> saveIps(List<int> answers) =>
      _write(_insights.saveIps(logicalDate(clock.now()), answers));
  Future<void> startExperiment(Experiment e) =>
      _write(_insights.saveExperiment(sprintId(logicalDate(clock.now())), e));
  Future<void> clearExperiment() => _write(
    _insights.saveExperiment(sprintId(logicalDate(clock.now())), null),
  );
  Future<void> saveReview(WeekReview r) =>
      _write(_insights.saveReview(sprintId(logicalDate(clock.now())), r));
  Future<void> setVerdict(String id, Verdict v) async {
    final sprint = state.sprint?.id == id
        ? state.sprint
        : state.previous?.id == id
        ? state.previous
        : null;
    final e = sprint?.experiment;
    if (e == null) return;
    await _write(
      _insights.saveExperiment(
        id,
        Experiment(
          hypothesis: e.hypothesis,
          strategy: e.strategy,
          metric: e.metric,
          baseline: e.baseline,
          verdict: v,
        ),
      ),
    );
  }

  void reportDeferral(Episode e, int count) =>
      emit(state.copyWith(lastDeferral: (episode: e, count: count)));
}
