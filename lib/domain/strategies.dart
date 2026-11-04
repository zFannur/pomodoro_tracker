import '../app/strings.dart';
import 'entities/episode.dart';
import 'entities/experiment.dart';
import 'insights.dart';

/// Порядок перечисления способов совпадает с порядком таблицы.
Set<Cause> causesOf(StrategyKind k) => switch (k) {
  StrategyKind.firstStep => {Cause.unclear, Cause.big},
  StrategyKind.warmup => {Cause.boring, Cause.tired, Cause.big},
  StrategyKind.ifThen => {Cause.unclear, Cause.boring, Cause.external},
  StrategyKind.shrink => {Cause.big},
  StrategyKind.thought => {Cause.perfect, Cause.big, Cause.pointless},
  StrategyKind.defuse => {Cause.perfect, Cause.boring},
  StrategyKind.value => {Cause.pointless},
  StrategyKind.rest => {Cause.tired},
  StrategyKind.removeCue => {Cause.external},
};

List<StrategyKind> candidates(Cause c) =>
    StrategyKind.values.where((k) => causesOf(k).contains(c)).toList();

List<StrategyKind> rankFor(
  Cause c,
  Map<StrategyKind, ({int tries, int wins})> stats, {
  StrategyKind? pinned,
}) {
  final result = candidates(c);
  result.sort((a, b) {
    if (a == pinned) return -1;
    if (b == pinned) return 1;
    final x = stats[a] ?? (tries: 0, wins: 0);
    final y = stats[b] ?? (tries: 0, wins: 0);
    final comparison = ((y.wins + 1) * (x.tries + 2)).compareTo(
      (x.wins + 1) * (y.tries + 2),
    );
    return comparison != 0 ? comparison : a.index.compareTo(b.index);
  });
  return result;
}

InsightMetric metricFor(StrategyKind k, {required bool hasTracker}) => switch (k) {
  StrategyKind.firstStep || StrategyKind.ifThen => InsightMetric.firstStart,
  StrategyKind.warmup || StrategyKind.defuse || StrategyKind.rest => InsightMetric.idle,
  StrategyKind.shrink || StrategyKind.thought || StrategyKind.value => InsightMetric.success,
  StrategyKind.removeCue => hasTracker ? InsightMetric.distract : InsightMetric.success,
};

Experiment? suggestExperiment(
  WeekInsight week,
  Map<StrategyKind, ({int tries, int wins})> stats, {
  required bool hasTracker,
}) {
  Cause? mostFrequent;
  var count = 0;
  for (final cause in Cause.values) {
    if (cause == Cause.external) continue;
    final current = week.causes[cause] ?? 0;
    if (current > count) {
      count = current;
      mostFrequent = cause;
    }
  }
  if (mostFrequent == null) return null;
  final strategy = rankFor(mostFrequent, stats).first;
  final metric = metricFor(strategy, hasTracker: hasTracker);
  return Experiment(
    hypothesis: S.hypothesis(strategy, metric),
    strategy: strategy,
    metric: metric,
    baseline: metricValue(week, metric),
  );
}
