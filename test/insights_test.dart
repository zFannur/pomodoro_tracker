import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/insights.dart';

void main() {
  final at = DateTime(2026, 1, 5, 10);
  PomoSession session(
    DateTime start, {
    int minutes = 25,
    bool manual = false,
    bool frog = false,
    int delay = 0,
  }) => PomoSession(
    id: '$start',
    start: start,
    minutes: minutes,
    manual: manual,
    frog: frog,
    delayMinutes: delay,
    category: '',
    task: '',
  );
  Episode episode({
    DateTime? time,
    EpisodeSource? source = EpisodeSource.idle,
    Cause? cause,
    StrategyKind? strategy,
  }) => Episode(
    id: 'e',
    at: time ?? at,
    source: source,
    cause: cause,
    strategy: strategy,
  );
  DayLog day(
    int n, {
    List<PomoSession> sessions = const [],
    List<Episode> episodes = const [],
    CheckIn checkIn = const CheckIn(),
  }) => DayLog(
    date: DateTime(2026, 1, n),
    goal: 0,
    sessions: sessions,
    episodes: episodes,
    checkIn: checkIn,
  );

  test('успех: строгие границы, длительность и ручные записи', () {
    final e = episode();
    for (final row in <(PomoSession, bool)>[
      (session(at.add(const Duration(minutes: 15))), false),
      (session(at.add(const Duration(minutes: 14))), true),
      (session(at, minutes: 4), false),
      (session(at, minutes: 5), true),
      (session(at, manual: true), false),
      (session(at.subtract(const Duration(minutes: 5)), minutes: 5), false),
      (session(at.subtract(const Duration(minutes: 5)), minutes: 6), true),
    ]) {
      expect(episodeSucceeded(e, [row.$1]), row.$2);
    }
    expect(episodeSucceeded(e, []), false);
  });

  test('метрики, порядок сессий, пороги и логические сутки', () {
    final days = [
      day(
        5,
        sessions: [
          session(DateTime(2026, 1, 5, 12), delay: 10),
          session(DateTime(2026, 1, 5, 8), frog: true),
          session(DateTime(2026, 1, 5, 7), manual: true, delay: 99),
        ],
      ),
      day(
        6,
        sessions: [
          session(DateTime(2026, 1, 6, 11), delay: 20),
          session(DateTime(2026, 1, 6, 10)),
        ],
      ),
      day(7, sessions: [session(DateTime(2026, 1, 8, 0, 30), frog: true)]),
    ];
    final w = weekInsight(days);
    expect(w.activeDays, 3);
    expect(w.firstStart, (180 + 300 + 1170) / 3);
    expect(w.firstStartIsLag, false);
    expect(w.idle, 15);
    expect(w.frogFirst, closeTo(200 / 3, 0.00001));
    final withWindows = weekInsight(
      days,
      windows: parseSessionWindows(['12:00-13:00', '09:00-11:00']),
    );
    expect(withWindows.firstStartIsLag, true);
    expect(withWindows.firstStart, (0 + 60 + 930) / 3);
    expect(weekInsight(days.take(2).toList()).firstStart, isNull);
    expect(weekInsight(days.take(2).toList()).frogFirst, isNull);
    expect(weekInsight(days.take(2).toList()).idle, isNull);
    expect(
      weekInsight([
        for (var n = 5; n < 10; n++)
          day(n, sessions: [session(DateTime(2026, 1, n, 9))]),
      ]).idle,
      isNull,
    );
  });

  test('эпизоды, способы, переносы и внешние причины', () {
    final episodes = [
      episode(
        source: EpisodeSource.defer,
        cause: Cause.external,
        strategy: StrategyKind.warmup,
      ),
      episode(
        source: EpisodeSource.frog,
        cause: Cause.big,
        strategy: StrategyKind.warmup,
      ),
      episode(source: null, strategy: StrategyKind.rest),
      episode(
        time: at.add(const Duration(hours: 2)),
        strategy: StrategyKind.rest,
      ),
    ];
    final w = weekInsight([
      day(5, sessions: [session(at)], episodes: episodes),
    ], distractPercent: 32);
    expect(w.episodes, 4);
    expect(w.deferrals, 1);
    expect(w.causes, {Cause.external: 1, Cause.big: 1});
    expect(w.strategies[StrategyKind.warmup], (tries: 2, wins: 2));
    expect(w.strategies[StrategyKind.rest], (tries: 2, wins: 1));
    expect(metricValue(w, InsightMetric.success), 75);
    expect(metricValue(w, InsightMetric.deferrals), 1);
    expect(metricValue(w, InsightMetric.distract), 32);
    expect(metricValue(weekInsight([]), InsightMetric.success), isNull);
    expect(
      metricValue(
        weekInsight([day(5, episodes: episodes.take(2).toList())]),
        InsightMetric.success,
      ),
      isNull,
    );
    expect(
      strategyStats([
        day(5, episodes: [episode(strategy: StrategyKind.rest)]),
        day(6, sessions: [session(at)]),
      ])[StrategyKind.rest]?.wins,
      0,
    );
  });

  test('вердикт: направления, 15%, ноль и недостаток данных', () {
    for (final metric in InsightMetric.values) {
      final lower = {
        InsightMetric.firstStart,
        InsightMetric.idle,
        InsightMetric.deferrals,
        InsightMetric.distract,
      }.contains(metric);
      expect(lowerIsBetter(metric), lower);
      Verdict v(double? base, double? now, [int days = 3]) =>
          verdictFor(metric: metric, baseline: base, now: now, days: days);
      expect(v(100, lower ? 85 : 115), Verdict.works);
      expect(v(100, lower ? 115 : 85), Verdict.worse);
      expect(v(100, 99), Verdict.same);
      expect(v(0, 0), Verdict.same);
      expect(v(0, 1), lower ? Verdict.worse : Verdict.works);
      expect(v(null, 1), Verdict.unclear);
      expect(v(1, null), Verdict.unclear);
      expect(v(1, 1, 2), Verdict.unclear);
    }
  });

  test('неделя наблюдения — самая ранняя логическая дата с эпизодом', () {
    final d = day(5, episodes: [episode(time: DateTime(2026, 1, 6, 0, 30))]);
    expect(
      baselineWeek([
        day(12, episodes: [episode()]),
        d,
      ]),
      '2026-W02',
    );
    expect(baselineWeek([]), isNull);
    expect(isObservationWeek('2026-W02', null), true);
    expect(isObservationWeek('2026-W02', '2026-W02'), true);
    expect(isObservationWeek('2026-W03', '2026-W02'), false);
  });

  test('разбиение самочувствия и пороги самой метрики', () {
    final days = [
      for (var n = 5; n < 8; n++)
        day(
          n,
          checkIn: const CheckIn(sleep: 4, energy: 1),
          sessions: [session(DateTime(2026, 1, n, 10))],
        ),
      for (var n = 8; n < 11; n++)
        day(
          n,
          checkIn: const CheckIn(sleep: 2, energy: 5),
          sessions: [session(DateTime(2026, 1, n, 9))],
        ),
      day(11, checkIn: const CheckIn(sleep: 3)),
      day(12),
    ];
    expect(
      checkInSplit(
        days.take(5).toList(),
        CheckInField.sleep,
        InsightMetric.firstStart,
      ),
      isNull,
    );
    final split = checkInSplit(
      days,
      CheckInField.sleep,
      InsightMetric.firstStart,
      windows: parseSessionWindows(['09:00-12:00']),
    );
    expect(split?.goodDays, 3);
    expect(split?.badDays, 3);
    expect(split?.good, 60);
    expect(split?.bad, 0);
    expect(
      checkInSplit(days, CheckInField.energy, InsightMetric.idle)?.good,
      isNull,
    );
    expect(
      checkInSplit(days, CheckInField.energy, InsightMetric.deferrals)?.bad,
      0,
    );
  });

  group('sessionsOfTask', () {
    PomoSession pomo(
      String id,
      DateTime start, {
      String taskId = '',
      String task = 'Подключить webhook',
      String category = 'work',
      bool manual = false,
    }) => PomoSession(
      id: id,
      start: start,
      minutes: 25,
      category: category,
      task: task,
      taskId: taskId,
      manual: manual,
    );

    test('по taskId, независимо от описания; порядок по старту', () {
      final days = [
        day(2, sessions: [pomo('b', at.add(const Duration(days: 1)), taskId: 't1')]),
        day(1, sessions: [
          pomo('a', at, taskId: 't1', task: 'Старое имя'),
          pomo('x', at, taskId: 't2'),
        ]),
      ];
      final result = sessionsOfTask(
        days,
        taskId: 't1',
        description: 'Подключить webhook',
        category: 'work',
      );
      expect(result.map((s) => s.id), ['a', 'b']);
    });

    test('старые записи без taskId — по описанию и категории', () {
      final days = [
        day(1, sessions: [
          pomo('old', at),
          pomo('other-cat', at, category: 'home'),
          pomo('other-desc', at, task: 'Другое'),
          pomo('new-other', at, taskId: 't2'),
        ]),
      ];
      final result = sessionsOfTask(
        days,
        taskId: 't1',
        description: 'Подключить webhook',
        category: 'work',
      );
      expect(result.map((s) => s.id), ['old']);
    });

    test('у задачи без id ищем по описанию и категории; ручные не берём', () {
      final days = [
        day(1, sessions: [
          pomo('a', at, taskId: 't1'),
          pomo('m', at, manual: true),
        ]),
      ];
      final result = sessionsOfTask(
        days,
        taskId: '',
        description: 'Подключить webhook',
        category: 'work',
      );
      expect(result.map((s) => s.id), ['a']);
    });
  });
}
