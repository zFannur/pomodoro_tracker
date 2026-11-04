import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../data/markdown_codec.dart' show sprintId;
import 'entities/episode.dart';
import 'entities/experiment.dart';
import 'entities/pomo_session.dart';
import 'entities/pomo_task.dart';

class WeekInsight extends Equatable {
  const WeekInsight({
    required this.activeDays,
    required this.firstStart,
    required this.firstStartIsLag,
    required this.idle,
    required this.frogFirst,
    required this.deferrals,
    required this.distract,
    required this.episodes,
    required this.causes,
    required this.strategies,
  });

  final int activeDays;
  final double? firstStart;
  final bool firstStartIsLag;
  final double? idle;
  final double? frogFirst;
  final int deferrals;
  final double? distract;
  final int episodes;
  final Map<Cause, int> causes;
  final Map<StrategyKind, ({int tries, int wins})> strategies;

  @override
  List<Object?> get props => [
    activeDays,
    firstStart,
    firstStartIsLag,
    idle,
    frogFirst,
    deferrals,
    distract,
    episodes,
    causes,
    strategies,
  ];
}

bool episodeSucceeded(Episode e, List<PomoSession> sessions) => sessions.any(
  (s) =>
      !s.manual &&
      s.minutes >= 5 &&
      s.start.isBefore(e.at.add(const Duration(minutes: 15))) &&
      s.start.add(Duration(minutes: s.minutes)).isAfter(e.at),
);

Map<StrategyKind, ({int tries, int wins})> strategyStats(List<DayLog> days) {
  final result = <StrategyKind, ({int tries, int wins})>{};
  for (final day in days) {
    for (final episode in day.episodes) {
      final strategy = episode.strategy;
      if (strategy == null) continue;
      final old = result[strategy] ?? (tries: 0, wins: 0);
      result[strategy] = (
        tries: old.tries + 1,
        wins: old.wins + (episodeSucceeded(episode, day.sessions) ? 1 : 0),
      );
    }
  }
  return result;
}

WeekInsight weekInsight(
  List<DayLog> days, {
  List<SessionWindow> windows = const [],
  double? distractPercent,
}) {
  var active = 0;
  var sessionsCount = 0;
  var frogDays = 0;
  var startTotal = 0.0;
  var delayTotal = 0;
  var delayCount = 0;
  var episodeCount = 0;
  var deferrals = 0;
  final causes = <Cause, int>{};
  // Первое окно определяется в порядке логических суток, а не полуночи.
  final firstWindow = windows.isEmpty
      ? null
      : windows
            .map(
              (w) => w.start < dayStartHour * 60 ? w.start + 24 * 60 : w.start,
            )
            .reduce(math.min);
  for (final day in days) {
    final sessions = day.sessions.where((s) => !s.manual).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    sessionsCount += sessions.length;
    if (sessions.isNotEmpty) {
      active++;
      final first = sessions.first;
      if (first.frog) frogDays++;
      final origin = DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
        0,
        firstWindow ?? dayStartHour * 60,
      );
      final minutes =
          first.start.difference(origin).inMicroseconds /
          Duration.microsecondsPerMinute;
      startTotal += firstWindow == null ? minutes : math.max(0, minutes);
      for (final session in sessions.skip(1)) {
        delayTotal += session.delayMinutes;
        delayCount++;
      }
    }
    episodeCount += day.episodes.length;
    for (final episode in day.episodes) {
      if (episode.source == EpisodeSource.defer) deferrals++;
      final cause = episode.cause;
      if (cause != null) causes[cause] = (causes[cause] ?? 0) + 1;
    }
  }
  return WeekInsight(
    activeDays: active,
    firstStart: active < 3 ? null : startTotal / active,
    firstStartIsLag: windows.isNotEmpty,
    idle: sessionsCount < 5 || delayCount == 0 ? null : delayTotal / delayCount,
    frogFirst: active < 3 ? null : frogDays * 100 / active,
    deferrals: deferrals,
    distract: distractPercent,
    episodes: episodeCount,
    causes: Map.unmodifiable(causes),
    strategies: Map.unmodifiable(strategyStats(days)),
  );
}

double? metricValue(WeekInsight w, InsightMetric m) => switch (m) {
  InsightMetric.firstStart => w.firstStart,
  InsightMetric.idle => w.idle,
  InsightMetric.frogFirst => w.frogFirst,
  InsightMetric.deferrals => w.deferrals.toDouble(),
  InsightMetric.distract => w.distract,
  InsightMetric.success => _success(w.strategies),
};

double? _success(Map<StrategyKind, ({int tries, int wins})> stats) {
  var tries = 0;
  var wins = 0;
  for (final value in stats.values) {
    tries += value.tries;
    wins += value.wins;
  }
  return tries < 3 ? null : wins * 100 / tries;
}

bool lowerIsBetter(InsightMetric m) => switch (m) {
  InsightMetric.firstStart ||
  InsightMetric.idle ||
  InsightMetric.deferrals ||
  InsightMetric.distract => true,
  InsightMetric.frogFirst || InsightMetric.success => false,
};

Verdict verdictFor({
  required InsightMetric metric,
  double? baseline,
  double? now,
  required int days,
}) {
  if (days < 3 || baseline == null || now == null) return Verdict.unclear;
  if (baseline == 0) {
    if (now == 0) return Verdict.same;
    return lowerIsBetter(metric) ? Verdict.worse : Verdict.works;
  }
  var delta = (now - baseline) / baseline;
  if (lowerIsBetter(metric)) delta = -delta;
  // Погрешность double не должна менять результат на границе 15%.
  const epsilon = 1e-12;
  if (delta >= 0.15 - epsilon) return Verdict.works;
  if (delta <= -0.15 + epsilon) return Verdict.worse;
  return Verdict.same;
}

String? baselineWeek(List<DayLog> days) {
  DateTime? earliest;
  for (final day in days) {
    if (day.episodes.isEmpty) continue;
    final date = DateTime(day.date.year, day.date.month, day.date.day);
    if (earliest == null || date.isBefore(earliest)) earliest = date;
  }
  return earliest == null ? null : sprintId(earliest);
}

bool isObservationWeek(String currentWeek, String? baseline) =>
    baseline == null || baseline == currentWeek;

enum CheckInField { sleep, energy }

class CheckInSplit {
  const CheckInSplit({
    required this.good,
    required this.bad,
    required this.goodDays,
    required this.badDays,
  });
  final double? good;
  final double? bad;
  final int goodDays;
  final int badDays;
}

CheckInSplit? checkInSplit(
  List<DayLog> days,
  CheckInField f,
  InsightMetric m, {
  List<SessionWindow> windows = const [],
}) {
  final good = <DayLog>[];
  final bad = <DayLog>[];
  for (final day in days) {
    final value = switch (f) {
      CheckInField.sleep => day.checkIn.sleep,
      CheckInField.energy => day.checkIn.energy,
    };
    if (value == null) continue;
    if (value >= 4) good.add(day);
    if (value <= 2) bad.add(day);
  }
  if (good.length < 3 || bad.length < 3) return null;
  return CheckInSplit(
    good: metricValue(weekInsight(good, windows: windows), m),
    bad: metricValue(weekInsight(bad, windows: windows), m),
    goodDays: good.length,
    badDays: bad.length,
  );
}

/// Пункты IPS (Svartdal & Steel 2017), которые считаются наоборот: 2, 6, 9.
const ipsReversed = {1, 5, 8};

/// Сумма баллов IPS: 9–45, меньше — лучше. Обратные пункты считаются как 6 − x.
/// null — ответов не девять или значение вне 1–5 (повреждённая запись).
int? ipsScore(List<int> answers) {
  if (answers.length != 9 || answers.any((a) => a < 1 || a > 5)) return null;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += ipsReversed.contains(i) ? 6 - answers[i] : answers[i];
  }
  return sum;
}
