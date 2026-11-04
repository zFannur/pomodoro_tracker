import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/insights.dart';
import 'package:pomodoro_tracker/domain/strategies.dart';

void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  test('соответствия и порядок таблицы для каждой причины', () {
    final expected = <Cause, List<StrategyKind>>{
      Cause.unclear: [StrategyKind.firstStep, StrategyKind.ifThen],
      Cause.big: [StrategyKind.firstStep, StrategyKind.warmup, StrategyKind.shrink, StrategyKind.thought],
      Cause.boring: [StrategyKind.warmup, StrategyKind.ifThen, StrategyKind.defuse],
      Cause.perfect: [StrategyKind.thought, StrategyKind.defuse],
      Cause.tired: [StrategyKind.warmup, StrategyKind.rest],
      Cause.pointless: [StrategyKind.thought, StrategyKind.value],
      Cause.external: [StrategyKind.ifThen, StrategyKind.removeCue],
    };
    for (final cause in Cause.values) {
      expect(candidates(cause), expected[cause]);
      expect(rankFor(cause, {}), expected[cause]);
    }
  });

  test('эксперимент закрепляет только подходящий способ', () {
    expect(rankFor(Cause.big, {}, pinned: StrategyKind.thought).first, StrategyKind.thought);
    expect(rankFor(Cause.big, {}, pinned: StrategyKind.rest), candidates(Cause.big));
  });

  test('сглаженные оценки и порядок при равенстве', () {
    expect(rankFor(Cause.big, {StrategyKind.thought: (tries: 3, wins: 3)}).first, StrategyKind.thought);
    expect(rankFor(Cause.big, {
      StrategyKind.firstStep: (tries: 6, wins: 4),
      StrategyKind.thought: (tries: 1, wins: 1),
    }).first, StrategyKind.thought);
    expect(rankFor(Cause.unclear, {
      StrategyKind.firstStep: (tries: 2, wins: 1),
      StrategyKind.ifThen: (tries: 0, wins: 0),
    }), candidates(Cause.unclear));
  });

  test('метрики для всех способов и трекера', () {
    expect([for (final k in StrategyKind.values) metricFor(k, hasTracker: true)], [
      InsightMetric.firstStart, InsightMetric.idle, InsightMetric.firstStart,
      InsightMetric.success, InsightMetric.success, InsightMetric.idle,
      InsightMetric.success, InsightMetric.idle, InsightMetric.distract,
    ]);
    expect(metricFor(StrategyKind.removeCue, hasTracker: false), InsightMetric.success);
  });

  test('предложение исключает внешнюю причину и сохраняет базу', () {
    WeekInsight week(Map<Cause, int> causes) => WeekInsight(
      activeDays: 3, firstStart: 42, firstStartIsLag: true, idle: null,
      frogFirst: null, deferrals: 0, distract: null, episodes: 5,
      causes: causes, strategies: const {},
    );
    expect(suggestExperiment(week({}), {}, hasTracker: true), isNull);
    expect(suggestExperiment(week({Cause.external: 5}), {}, hasTracker: true), isNull);
    final result = suggestExperiment(week({Cause.external: 10, Cause.unclear: 2, Cause.big: 1}), {}, hasTracker: true);
    expect(result?.strategy, StrategyKind.firstStep);
    expect(result?.metric, InsightMetric.firstStart);
    expect(result?.baseline, 42);
    expect(result?.hypothesis, S.hypothesis(StrategyKind.firstStep, InsightMetric.firstStart));
    expect(suggestExperiment(week({Cause.tired: 3}), {StrategyKind.rest: (tries: 3, wins: 3)}, hasTracker: false)?.strategy, StrategyKind.rest);
  });

  test('все новые тексты доступны на обоих языках', () {
    for (final language in AppLanguage.values) {
      S.lang = language;
      for (final c in Cause.values) { expect(S.cause(c), isNotEmpty); }
      for (final k in StrategyKind.values) {
        expect(S.strategyTitle(k), isNotEmpty);
        expect(S.strategyBody(k), isNotEmpty);
        for (final m in InsightMetric.values) { expect(S.hypothesis(k, m), contains(S.metric(m))); }
      }
      for (final v in Verdict.values) { expect(S.verdict(v), isNotEmpty); }
      expect(S.defuseLine('test'), contains('test'));
      for (final text in [S.causeFinished, S.actionWarmup, S.actionSaveWarmup, S.actionSave,
        S.actionRest, S.actionToInbox, S.actionAddStart, S.actionContinue, S.fieldFirstStep,
        S.fieldCue, S.fieldCueAt, S.fieldShrink, S.fieldThought, S.fieldFact, S.fieldAlt,
        S.fieldWhy, S.fieldToInbox, S.valueNoDirection]) { expect(text, isNotEmpty); }
    }
  });
}
