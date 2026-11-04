import 'package:equatable/equatable.dart';

import 'episode.dart';

enum InsightMetric { firstStart, idle, frogFirst, deferrals, distract, success }

enum Verdict { works, same, worse, unclear }

class Experiment extends Equatable {
  const Experiment({
    required this.hypothesis,
    required this.strategy,
    required this.metric,
    this.baseline,
    this.verdict,
  });

  final String hypothesis;
  final StrategyKind strategy;
  final InsightMetric metric;

  /// null — у прошлой недели недостаточно данных.
  final double? baseline;

  /// null — неделя ещё идёт или итог не подтверждён.
  final Verdict? verdict;

  @override
  List<Object?> get props => [hypothesis, strategy, metric, baseline, verdict];
}

/// Кеш разбора нужен и без повторного обращения к ИИ.
class WeekReview extends Equatable {
  const WeekReview({
    required this.at,
    required this.summary,
    this.patterns = const [],
  });

  final DateTime at;
  final String summary;
  final List<({String text, String evidence})> patterns;

  @override
  List<Object?> get props => [at, summary, patterns];
}
