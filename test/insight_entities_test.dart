import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

void main() {
  final at = DateTime(2026, 11, 4, 10, 15);
  final episode = Episode(
    id: 'e',
    at: at,
    source: EpisodeSource.manual,
    taskId: 'task',
    task: 'задача',
    category: 'код',
    cause: Cause.big,
    strategy: StrategyKind.thought,
    thought: 'мысль',
    fact: 'факт',
    alt: 'точнее',
    app: 'окно',
  );
  const experiment = Experiment(
    hypothesis: 'первый шаг помогает',
    strategy: StrategyKind.firstStep,
    metric: InsightMetric.firstStart,
    baseline: 0,
    verdict: Verdict.works,
  );
  final review = WeekReview(
    at: at,
    summary: 'итог',
    patterns: const [(text: 'связь', evidence: '3 дня')],
  );

  test('Episode: copyWith сохраняет поля, меняет все поля и очищает ответ', () {
    expect(episode.copyWith(), episode);
    final changed = episode.copyWith(
      id: 'new',
      at: at.add(const Duration(minutes: 1)),
      source: EpisodeSource.stop,
      taskId: 't2',
      task: 'другая',
      category: 'личное',
      cause: Cause.tired,
      strategy: StrategyKind.rest,
      thought: 'т',
      fact: 'ф',
      alt: 'а',
      app: 'браузер',
    );
    expect(changed, isNot(episode));
    expect(changed.props, [
      'new',
      at.add(const Duration(minutes: 1)),
      EpisodeSource.stop,
      't2',
      'другая',
      'личное',
      Cause.tired,
      StrategyKind.rest,
      'т',
      'ф',
      'а',
      'браузер',
    ]);
    final cleared = episode.copyWith(
      cause: Cause.tired,
      clearCause: true,
      strategy: StrategyKind.rest,
      clearStrategy: true,
    );
    expect(cleared.cause, isNull);
    expect(cleared.strategy, isNull);
    expect(cleared.thought, episode.thought);
  });

  test('CheckIn: пустота, диапазон и непустые поля other поверх', () {
    expect(const CheckIn().isEmpty, isTrue);
    const morning = CheckIn(sleep: 4, energy: 3);
    expect(morning.isEmpty, isFalse);
    expect(
      morning.merge(const CheckIn(mood: 5)),
      const CheckIn(sleep: 4, energy: 3, mood: 5),
    );
    expect(
      morning.merge(const CheckIn(sleep: 2)),
      const CheckIn(sleep: 2, energy: 3),
    );
    expect(morning.merge(const CheckIn()), morning);
    expect(() => CheckIn(sleep: 0), throwsAssertionError);
    expect(() => CheckIn(energy: 6), throwsAssertionError);
    expect(() => CheckIn(mood: -1), throwsAssertionError);
  });

  test('DayLog: новые поля участвуют в copyWith и равенстве', () {
    final day = DayLog(date: at, goal: 8, sessions: const []);
    final withEpisode = day.copyWith(episodes: [episode]);
    final withCheckIn = day.copyWith(checkIn: const CheckIn(sleep: 4));
    final withIps = day.copyWith(ips: const [1, 2, 3]);
    expect(withEpisode, isNot(day));
    expect(withCheckIn, isNot(day));
    expect(withIps, isNot(day));
    final full = withEpisode.copyWith(
      checkIn: withCheckIn.checkIn,
      ips: withIps.ips,
    );
    expect(full.copyWith(), full);
    expect(full.episodes, [episode]);
    expect(full.checkIn, withCheckIn.checkIn);
    expect(full.ips, withIps.ips);
  });

  test('Sprint, Experiment, WeekReview: равенство и clearExperiment', () {
    final sprint = Sprint(id: '2026-W45', start: at, goal: 40);
    final full = sprint.copyWith(experiment: experiment, review: review);
    expect(full, isNot(sprint));
    expect(full.copyWith(), full);
    expect(full.copyWith(clearExperiment: true).experiment, isNull);
    expect(full.copyWith(clearExperiment: true).review, review);
    expect(experiment.props, [
      'первый шаг помогает',
      StrategyKind.firstStep,
      InsightMetric.firstStart,
      0.0,
      Verdict.works,
    ]);
    expect(
      review,
      WeekReview(
        at: at,
        summary: 'итог',
        patterns: const [(text: 'связь', evidence: '3 дня')],
      ),
    );
    expect(review, isNot(WeekReview(at: at, summary: 'другое')));
    expect(sprint.copyWith(experiment: experiment), isNot(sprint));
    expect(sprint.copyWith(review: review), isNot(sprint));
  });
}
