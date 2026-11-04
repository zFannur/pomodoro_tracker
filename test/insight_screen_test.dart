import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/domain/insights.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/home_shell.dart';
import 'package:pomodoro_tracker/presentation/screens/insight_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/sprint_screen.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

class _MemoryActivityStore extends ActivityStore {
  @override
  Future<ActivityData> load() async => ActivityData();

  @override
  Future<void> save(ActivityData data) async {}
}

/// InsightCubit с готовыми данными: записи не ходят в репозиторий,
/// а складываются в списки для проверки.
class ReviewInsight extends InsightCubit {
  ReviewInsight({
    List<DayLog> days = const [],
    Sprint? sprint,
    Sprint? previous,
  }) : super(FakeInsights(), FakeJournal(), FakeSprints(), episodeSettings) {
    emit(
      InsightState(
        status: InsightStatus.ready,
        days: days,
        sprint: sprint,
        previous: previous,
      ),
    );
  }

  final verdicts = <(String, Verdict)>[];
  final started = <Experiment>[];
  final ips = <List<int>>[];
  final deleted = <String>[];
  int cleared = 0;

  @override
  Future<void> refresh() async {}
  @override
  Future<void> setVerdict(String id, Verdict v) async => verdicts.add((id, v));
  @override
  Future<void> startExperiment(Experiment e) async => started.add(e);
  @override
  Future<void> clearExperiment() async => cleared++;
  @override
  Future<void> saveIps(List<int> answers) async => ips.add(answers);
  @override
  Future<void> deleteEpisode(String id) async => deleted.add(id);
}

const _longTask =
    'Подготовить подробный отчёт по результатам квартала для всей команды';
const _longHypothesis =
    'Если у задачи есть первый шаг на пять минут, я начинаю работу заметно '
    'раньше и меньше времени теряю на раздумья перед стартом';

// Среда, 4 ноября 2026 (W45). Прошлая неделя W44 — с 26 октября.
final _now = DateTime(2026, 11, 4, 10);

PomoSession _session(DateTime day, int hour, {bool frog = false, int delay = 0}) =>
    PomoSession(
      id: '${day.day}-$hour',
      start: DateTime(day.year, day.month, day.day, hour),
      minutes: 25,
      category: 'работа',
      task: 'задача',
      frog: frog,
      delayMinutes: delay,
    );

Episode _episode(
  String id,
  DateTime at, {
  EpisodeSource source = EpisodeSource.idle,
  Cause? cause,
  StrategyKind? strategy,
  String task = _longTask,
  String app = '',
}) => Episode(
  id: id,
  at: at,
  source: source,
  task: task,
  cause: cause,
  strategy: strategy,
  app: app,
);

/// Два помидора в день; [good] — сон 4+ и первая 🐸, иначе сон 1–2.
DayLog _day(
  DateTime date, {
  required int sleep,
  bool frog = false,
  int delay = 0,
  List<Episode> episodes = const [],
  List<int> ips = const [],
}) => DayLog(
  date: date,
  goal: 8,
  sessions: [
    _session(date, 9, frog: frog),
    _session(date, 10, delay: delay),
  ],
  episodes: episodes,
  checkIn: CheckIn(sleep: sleep),
  ips: ips,
);

/// Неделя W44 (база) и текущая W45. [observed] — эпизоды только в W45.
List<DayLog> _days({bool observed = false, List<DayLog> extra = const []}) {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  DateTime at(int month, int day, int h, int m) =>
      DateTime(2026, month, day, h, m);
  return [
    ...extra,
    _day(
      d(10, 27),
      sleep: 1,
      delay: 10,
      episodes: observed
          ? const []
          : [
              _episode('a1', at(10, 27, 8, 50), cause: Cause.unclear),
              _episode('a2', at(10, 27, 9, 30), cause: Cause.unclear),
              _episode('a3', at(10, 27, 11, 0), cause: Cause.boring),
            ],
    ),
    _day(d(10, 28), sleep: 2, delay: 10),
    _day(d(10, 29), sleep: 2, delay: 10),
    _day(
      d(11, 2),
      sleep: 5,
      frog: true,
      delay: 2,
      episodes: [
        _episode(
          'b0',
          at(11, 2, 7, 0),
          cause: Cause.boring,
          source: EpisodeSource.manual,
        ),
      ],
    ),
    _day(
      d(11, 3),
      sleep: 4,
      frog: true,
      delay: 2,
      episodes: [
        _episode(
          'b1',
          at(11, 3, 8, 50),
          cause: Cause.unclear,
          strategy: StrategyKind.firstStep,
        ),
        _episode('b2', at(11, 3, 12, 0), cause: Cause.unclear),
        _episode('b3', at(11, 3, 13, 0), cause: Cause.perfect),
        _episode(
          'b4',
          at(11, 3, 14, 0),
          cause: Cause.external,
          source: EpisodeSource.distract,
          app: 'YouTube',
        ),
        _episode(
          'b5',
          at(11, 3, 23, 59),
          source: EpisodeSource.frog,
          task: 'Написать договор',
        ),
      ],
    ),
    _day(
      d(11, 4),
      sleep: 4,
      frog: true,
      delay: 2,
      episodes: [
        _episode('c1', at(11, 4, 9, 40)),
        _episode(
          'c2',
          at(11, 4, 9, 50),
          source: EpisodeSource.stop,
          cause: Cause.tired,
        ),
      ],
    ),
  ];
}

Sprint _sprint({Experiment? experiment, WeekReview? review}) => Sprint(
  id: '2026-W45',
  start: DateTime(2026, 11, 2),
  goal: 40,
  experiment: experiment,
  review: review,
);

Sprint _previousSprint({double? baseline = 40, Verdict? verdict}) => Sprint(
  id: '2026-W44',
  start: DateTime(2026, 10, 26),
  goal: 40,
  experiment: Experiment(
    hypothesis: _longHypothesis,
    strategy: StrategyKind.firstStep,
    metric: InsightMetric.firstStart,
    baseline: baseline,
    verdict: verdict,
  ),
);

Future<(ScreenHarness, ReviewInsight)> _open(
  WidgetTester tester, {
  ReviewInsight? insight,
  Size size = const Size(375, 3200),
  bool showWindows = false,
  Widget? screen,
}) async {
  final cubit =
      insight ??
      ReviewInsight(
        days: _days(),
        sprint: _sprint(),
        previous: _previousSprint(),
      );
  final h = await pumpScreen(
    tester,
    size,
    screen ?? InsightScreen(showWindows: showWindows),
    insightCubit: cubit,
  );
  return (h, cubit);
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(375, 3200), const Size(1280, 3200)]) {
    testWidgets('строится без переполнения: ${size.width.toInt()} px', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        // Предыдущий эксперимент и предложение — самые длинные тексты.
        final (h, _) = await _open(tester, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text(S.insightWeekTitle('W45')), findsOneWidget);
        expect(find.text(S.experimentTake), findsOneWidget);
        await _tapTab(tester, S.insightTabEpisodes);
        expect(tester.takeException(), isNull);
        expect(find.text(_longTask), findsWidgets);
        await h.dispose();
      });
    });
  }

  testWidgets('текущий эксперимент с длинной гипотезой — без переполнения', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final insight = ReviewInsight(
        days: _days(),
        sprint: _sprint(
          experiment: const Experiment(
            hypothesis: _longHypothesis,
            strategy: StrategyKind.firstStep,
            metric: InsightMetric.firstStart,
            baseline: 40,
          ),
          review: WeekReview(
            at: _now,
            summary: _longHypothesis,
            patterns: const [(text: _longHypothesis, evidence: _longTask)],
          ),
        ),
        previous: _previousSprint(verdict: Verdict.works),
      );
      final (h, _) = await _open(
        tester,
        insight: insight,
        size: const Size(320, 3200),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(S.experimentClear), findsOneWidget);
      expect(find.text(S.reviewTitle), findsOneWidget);
      await _tapTab(tester, S.insightTabEpisodes);
      expect(tester.takeException(), isNull);
      await h.dispose();
    });
  });

  testWidgets('showWindows: false — две вкладки', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(tester);
      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.text(S.insightTabWindows), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('неделя наблюдения — подпись в заголовке, предложения нет', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(
        tester,
        insight: ReviewInsight(days: _days(observed: true), sprint: _sprint()),
      );
      expect(
        find.textContaining(S.insightObservationSuffix, findRichText: true),
        findsOneWidget,
      );
      expect(find.text(S.experimentTake), findsNothing);
      expect(find.text(S.experimentAfterObservation), findsOneWidget);
      await h.dispose();
    });
  });

  testWidgets('плитки: значение, Δ к прошлой неделе и база', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(tester, size: const Size(1280, 3200));
      // Старт в 09:00 обеих недель: Δ нет, «база» совпадает со значением.
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text(S.insightBase('09:00')), findsOneWidget);
      // 🐸 первой: 3 из 3 против 0 из 3 на прошлой неделе.
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('▲ 100%'), findsOneWidget);
      // Простой 2 мин против 10: стало лучше.
      expect(find.text('▼ 8'), findsOneWidget);
      await h.dispose();
    });
  });

  testWidgets('причины и самочувствие → дела', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(tester, size: const Size(1280, 3200));
      expect(find.text(S.cause(Cause.unclear)), findsOneWidget);
      expect(find.text(S.causeExternal(1)), findsOneWidget);
      expect(
        find.text(
          S.causeBest(S.strategyTitle(StrategyKind.firstStep), 1, 1),
        ),
        findsOneWidget,
      );
      expect(
        find.text(S.wellbeingLine('Сон', 'Простой', '2 мин', '10 мин')),
        findsOneWidget,
      );
      expect(find.text(S.causesEmpty), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('без данных: подсказки вместо причин и самочувствия', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(
        tester,
        insight: ReviewInsight(sprint: _sprint()),
      );
      expect(find.text(S.causesEmpty), findsOneWidget);
      expect(find.text(S.wellbeingHint), findsOneWidget);
      expect(find.text(S.insightNoData), findsWidgets);
      await h.dispose();
    });
  });

  testWidgets('вердикт прошлой недели вызывает setVerdict', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, insight) = await _open(tester);
      // Расчётный вердикт предвыбран: старт 09:00 против базы 40 мин — хуже.
      final button = tester.widget<SegmentedButton<Verdict>>(
        find.byType(SegmentedButton<Verdict>),
      );
      expect(button.selected, {Verdict.worse});
      await tester.tap(find.text(S.verdictButton(Verdict.works)));
      await tester.pump();
      expect(insight.verdicts, [('2026-W44', Verdict.works)]);
      await h.dispose();
    });
  });

  testWidgets('мало данных: вердикт не выбран, подпись «мало данных»', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final insight = ReviewInsight(
        days: _days(),
        sprint: _sprint(),
        previous: _previousSprint(baseline: null),
      );
      final (h, _) = await _open(tester, insight: insight);
      final button = tester.widget<SegmentedButton<Verdict>>(
        find.byType(SegmentedButton<Verdict>),
      );
      expect(button.selected, isEmpty);
      await h.dispose();
    });
  });

  testWidgets('«Взять» запускает предложенный эксперимент', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, insight) = await _open(tester);
      await _scrollTo(tester, find.text(S.experimentTake));
      await tester.tap(find.text(S.experimentTake));
      await tester.pump();
      expect(insight.started, hasLength(1));
      final e = insight.started.single;
      expect(e.strategy, StrategyKind.firstStep);
      expect(e.metric, InsightMetric.firstStart);
      expect(e.baseline, 240);
      expect(e.hypothesis, S.hypothesis(e.strategy, e.metric));
      await h.dispose();
    });
  });

  testWidgets('«Не сейчас» скрывает предложение', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, insight) = await _open(tester);
      await _scrollTo(tester, find.text(S.experimentLater));
      await tester.tap(find.text(S.experimentLater));
      await tester.pump();
      expect(find.text(S.experimentTake), findsNothing);
      expect(insight.started, isEmpty);
      await h.dispose();
    });
  });

  testWidgets('«Свой…» — диалог с гипотезой, способом и метрикой', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, insight) = await _open(tester);
      await _scrollTo(tester, find.text(S.experimentCustom));
      await tester.tap(find.text(S.experimentCustom));
      await tester.pumpAndSettle();
      expect(find.text(S.experimentCustomTitle), findsOneWidget);
      // Смена способа переписывает нетронутую гипотезу и подбирает метрику.
      await tester.tap(find.byKey(const ValueKey('experiment-strategy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.strategyTitle(StrategyKind.warmup)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();
      expect(insight.started, hasLength(1));
      final e = insight.started.single;
      expect(e.strategy, StrategyKind.warmup);
      expect(e.metric, InsightMetric.idle);
      expect(e.hypothesis, S.hypothesis(StrategyKind.warmup, InsightMetric.idle));
      await h.dispose();
    });
  });

  testWidgets('«Снять» убирает текущий эксперимент', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final insight = ReviewInsight(
        days: _days(),
        sprint: _sprint(
          experiment: const Experiment(
            hypothesis: 'Если разгоняться, простой короче',
            strategy: StrategyKind.warmup,
            metric: InsightMetric.idle,
            baseline: 10,
          ),
        ),
      );
      final (h, _) = await _open(tester, insight: insight);
      expect(find.text(S.experimentTake), findsNothing);
      await tester.tap(find.text(S.experimentClear));
      expect(insight.cleared, 1);
      await h.dispose();
    });
  });

  group('шкала IPS', () {
    testWidgets('первая неделя месяца — карточка; диалог сохраняет 9 чисел', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, insight) = await _open(tester);
        await _scrollTo(tester, find.text(S.ipsTake));
        await tester.tap(find.text(S.ipsTake));
        await tester.pumpAndSettle();

        FilledButton save() =>
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, S.save));
        expect(save().onPressed, isNull);
        for (var i = 0; i < 9; i++) {
          final chip = find.byKey(ValueKey('ips:$i:${i % 5 + 1}'));
          await _scrollTo(tester, chip);
          await tester.tap(chip);
          await tester.pump();
          // Пока не отвечены все девять, сохранить нельзя.
          expect(save().onPressed == null, i < 8);
        }
        await tester.tap(find.widgetWithText(FilledButton, S.save));
        await tester.pumpAndSettle();
        expect(insight.ips, [
          [for (var i = 0; i < 9; i++) i % 5 + 1],
        ]);
        expect(tester.takeException(), isNull);
        await h.dispose();
      });
    });

    testWidgets('после 7-го числа или с готовым результатом карточки нет', (
      tester,
    ) async {
      await withClock(Clock.fixed(DateTime(2026, 11, 12, 10)), () async {
        final (h, _) = await _open(tester);
        expect(find.text(S.ipsTake), findsNothing);
        await h.dispose();
      });
      await withClock(Clock.fixed(_now), () async {
        final done = _day(
          DateTime(2026, 11, 1),
          sleep: 3,
          ips: const [3, 3, 3, 3, 3, 3, 3, 3, 3],
        );
        final (h, _) = await _open(
          tester,
          insight: ReviewInsight(
            days: _days(extra: [done]),
            sprint: _sprint(),
          ),
        );
        expect(find.text(S.ipsTake), findsNothing);
        await h.dispose();
      });
    });

    testWidgets('история — по месяцам, с двух результатов', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        const aug = [3, 3, 3, 3, 3, 3, 3, 3, 3];
        const sep = [5, 1, 5, 5, 5, 1, 5, 5, 1];
        final (h, _) = await _open(
          tester,
          insight: ReviewInsight(
            days: _days(
              extra: [
                _day(DateTime(2026, 8, 31), sleep: 3, ips: aug),
                _day(DateTime(2026, 9, 29), sleep: 3, ips: sep),
              ],
            ),
            sprint: _sprint(),
          ),
        );
        // Все 3 → 27; нормальные по 5 и обратные по 1 → 6·5 + 3·(6−1).
        expect(ipsScore(aug), 27);
        expect(ipsScore(sep), 45);
        expect(find.text('${S.monthShort(8)} 27 · ${S.monthShort(9)} 45'),
            findsOneWidget);
        await h.dispose();
      });
    });

    test('сумма: обратные пункты 2, 6 и 9; битая запись — null', () {
      expect(ipsScore(List.filled(9, 5)), 33);
      expect(ipsScore(List.filled(9, 1)), 21);
      expect(ipsScore(const [1, 2, 3]), isNull);
      expect(ipsScore(const [1, 2, 3, 4, 5, 1, 2, 3, 6]), isNull);
    });
  });

  group('эпизоды', () {
    testWidgets('группы по дням, иконки источников, ✓ для способа', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, _) = await _open(tester, size: const Size(1280, 3200));
        await _tapTab(tester, S.insightTabEpisodes);
        expect(find.text(S.periodToday), findsOneWidget);
        expect(find.text(S.dayHeader(DateTime(2026, 11, 3))), findsOneWidget);
        expect(find.text('Вт, 3 ноября'), findsOneWidget);
        expect(find.byIcon(Icons.hourglass_empty), findsWidgets);
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new), findsOneWidget);
        expect(find.text('🐸'), findsOneWidget);
        expect(find.text(S.episodeDistract('YouTube')), findsOneWidget);
        // Эпизод b1 со способом: помидор в 09:00 начат в пределах 15 минут.
        expect(find.text('✓'), findsOneWidget);
        await h.dispose();
      });
    });

    testWidgets('эпизод без причины: тап по «—» открывает лист', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, _) = await _open(tester);
        await _tapTab(tester, S.insightTabEpisodes);
        await tester.tap(find.byKey(const ValueKey('episode-cause:c1')));
        await tester.pumpAndSettle();
        expect(find.text(S.episodeTitle), findsOneWidget);
        await h.dispose();
      });
    });

    testWidgets('фильтр по причине: тап отбирает, повторный снимает', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, _) = await _open(tester, size: const Size(1280, 3200));
        await _tapTab(tester, S.insightTabEpisodes);
        final chip = find.byKey(const ValueKey('episode-filter:perfect'));
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('episode-cause:b3')), findsOneWidget);
        expect(find.byKey(const ValueKey('episode-cause:b2')), findsNothing);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('episode-cause:b2')), findsOneWidget);
        await h.dispose();
      });
    });

    testWidgets('«Удалить» вызывает deleteEpisode и показывает снекбар', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, insight) = await _open(tester);
        await _tapTab(tester, S.insightTabEpisodes);
        await tester.tap(find.byKey(const ValueKey('episode-menu:c1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(S.delete));
        await tester.pump();
        expect(insight.deleted, ['c1']);
        expect(find.text(S.episodeDeleted), findsOneWidget);
        // Снекбар без действия «Отмена».
        expect(find.byType(SnackBarAction), findsNothing);
        await h.dispose();
      });
    });

    testWidgets('нет эпизодов — сообщение', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        final (h, _) = await _open(
          tester,
          insight: ReviewInsight(sprint: _sprint()),
        );
        await _tapTab(tester, S.insightTabEpisodes);
        expect(find.text(S.episodesEmpty), findsOneWidget);
        await h.dispose();
      });
    });
  });

  testWidgets('карточка эксперимента на Спринте ведёт на «Разбор»', (
    tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      const experiment = Experiment(
        hypothesis: _longHypothesis,
        strategy: StrategyKind.firstStep,
        metric: InsightMetric.firstStart,
        baseline: 40,
      );
      final insight = ReviewInsight(
        days: _days(),
        sprint: _sprint(experiment: experiment),
      );
      final (h, _) = await _open(
        tester,
        insight: insight,
        screen: const SprintScreen(),
      );
      expect(tester.takeException(), isNull);
      homeTab.value = 0;
      final card = find.textContaining('🧪');
      expect(card, findsOneWidget);
      await tester.tap(card);
      expect(homeTab.value, kInsightTab);
      await h.dispose();
    });
  });

  testWidgets('без эксперимента Спринт не показывает карточку', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      final (h, _) = await _open(
        tester,
        insight: ReviewInsight(days: _days(), sprint: _sprint()),
        screen: const SprintScreen(),
      );
      expect(find.textContaining('🧪'), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('HomeShell: homeTab переключает вкладку и зеркалит выбор', (
    tester,
  ) async {
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await withClock(Clock.fixed(_now), () async {
      final tracker = ActivityTracker(
        store: _MemoryActivityStore(),
        inPomodoro: () => false,
      );
      final activity = ActivityCubit(tracker);
      final h = await pumpScreen(
        tester,
        const Size(1280, 900),
        BlocProvider.value(value: activity, child: const HomeShell()),
        insightCubit: ReviewInsight(days: _days(), sprint: _sprint()),
      );
      int selected() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex!;
      expect(selected(), 0);
      expect(homeTab.value, 0);
      homeTab.value = kInsightTab;
      await tester.pumpAndSettle();
      expect(selected(), kInsightTab);
      expect(find.text(S.navInsight), findsOneWidget);
      // Обычный выбор в навигации попадает обратно в homeTab.
      await tester.tap(find.text(S.navSprint));
      await tester.pumpAndSettle();
      expect(homeTab.value, 2);
      expect(tester.takeException(), isNull);
      await h.dispose();
      await tester.runAsync(activity.close);
      await tester.runAsync(tracker.dispose);
    });
  });
}
