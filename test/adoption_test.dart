import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/help_content.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/adoption.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

/// Факты, при которых шаг выполнен, и факты, при которых нет.
/// Ключи — все id таблицы «Путь внедрения»; ручные шаги проверяются отдельно.
final _done = <String, AdoptionFacts>{
  'setup.dirs': const AdoptionFacts(activeDirections: 2),
  'setup.cats': const AdoptionFacts(
    activeDirections: 2,
    directionsWithCategories: 2,
  ),
  'setup.ladder': const AdoptionFacts(
    activeDirections: 2,
    directionsWithLadder: 2,
  ),
  'setup.windows': const AdoptionFacts(hasSessionWindows: true),
  'setup.distract': const AdoptionFacts(hasDistractMarks: true),
  'setup.ai': const AdoptionFacts(aiKeySet: true),
  'observe.checkin': const AdoptionFacts(checkinMornings: 3),
  'observe.causes': const AdoptionFacts(causeEpisodes: 5),
  'observe.frog': const AdoptionFacts(frogDays: 3),
  'exp.take': const AdoptionFacts(hasExperiment: true),
  'exp.strategies': const AdoptionFacts(strategyEpisodes: 3),
  'exp.firststep': const AdoptionFacts(todayHasFirstStep: true),
  'plan.ifthen': const AdoptionFacts(todayHasCue: true),
  'plan.verdict': const AdoptionFacts(previousVerdict: true),
  'plan.warmup': const AdoptionFacts(warmupUsed: true),
  'own.scale': const AdoptionFacts(ipsThisMonth: true),
};

final _notYet = <String, AdoptionFacts>{
  'setup.dirs': const AdoptionFacts(activeDirections: 1),
  // Направления есть, но у одного нет категорий / короткая лестница.
  'setup.cats': const AdoptionFacts(
    activeDirections: 2,
    directionsWithCategories: 1,
  ),
  'setup.ladder': const AdoptionFacts(
    activeDirections: 2,
    directionsWithLadder: 1,
  ),
  'observe.checkin': const AdoptionFacts(checkinMornings: 2),
  'observe.causes': const AdoptionFacts(causeEpisodes: 4),
  'observe.frog': const AdoptionFacts(frogDays: 2),
  'exp.strategies': const AdoptionFacts(strategyEpisodes: 2),
};

const _manual = [
  'observe.nofix',
  'exp.read',
  'own.compare',
  'own.keep',
  'own.month',
];

Set<String> _allIds() => {
  for (final st in adoptionStages()) ...st.steps.map((s) => s.id),
};

void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  test('таблица покрывает каждый шаг пути', () {
    expect({..._done.keys, ..._manual}, _allIds());
  });

  group('stepDone', () {
    for (final entry in _done.entries) {
      test('${entry.key}: выполнен по фактам', () {
        expect(stepDone(entry.key, entry.value, {}), isTrue);
      });
      test('${entry.key}: без фактов не выполнен', () {
        expect(stepDone(entry.key, const AdoptionFacts(), {}), isFalse);
      });
    }
    for (final entry in _notYet.entries) {
      test('${entry.key}: ниже порога не выполнен', () {
        expect(stepDone(entry.key, entry.value, {}), isFalse);
      });
    }
    for (final id in _manual) {
      test('$id: только вручную', () {
        // Никакие факты шаг не отмечают.
        expect(
          stepDone(
            id,
            const AdoptionFacts(
              activeDirections: 5,
              checkinMornings: 7,
              hasExperiment: true,
            ),
            {},
          ),
          isFalse,
        );
        expect(stepDone(id, const AdoptionFacts(), {id}), isTrue);
        expect(stepDone(id, const AdoptionFacts(), {'other'}), isFalse);
      });
    }

    test('автошаг не отмечается руками', () {
      expect(stepDone('exp.take', const AdoptionFacts(), {'exp.take'}), isFalse);
    });
  });

  group('currentStage', () {
    final stages = adoptionStages();
    const setup = AdoptionFacts(
      activeDirections: 2,
      directionsWithCategories: 2,
      directionsWithLadder: 2,
    );

    test('без данных — первый этап', () {
      expect(
        currentStage(stages, const AdoptionFacts(), {}, windows: true),
        0,
      );
    });

    test('необязательные шаги этап не держат', () {
      // Окна сессий и ИИ необязательны: без них первый этап пройден
      // (кроме «Windows»-шага, если он нужен).
      const withMarks = AdoptionFacts(
        activeDirections: 2,
        directionsWithCategories: 2,
        directionsWithLadder: 2,
        hasDistractMarks: true,
      );
      expect(currentStage(stages, withMarks, {}, windows: true), 1);
    });

    test('шаг «Windows» на других платформах не учитывается', () {
      expect(currentStage(stages, setup, {}, windows: false), 1);
      expect(currentStage(stages, setup, {}, windows: true), 0);
    });

    test('ручной шаг держит этап, пока не отмечен', () {
      const second = AdoptionFacts(
        activeDirections: 2,
        directionsWithCategories: 2,
        directionsWithLadder: 2,
        checkinMornings: 3,
        causeEpisodes: 5,
        frogDays: 3,
      );
      expect(currentStage(stages, second, {}, windows: false), 1);
      expect(
        currentStage(stages, second, {'observe.nofix'}, windows: false),
        2,
      );
    });

    test('путь пройден — stages.length', () {
      const all = AdoptionFacts(
        activeDirections: 2,
        directionsWithCategories: 2,
        directionsWithLadder: 2,
        hasDistractMarks: true,
        checkinMornings: 7,
        causeEpisodes: 9,
        frogDays: 7,
        hasExperiment: true,
        strategyEpisodes: 5,
        todayHasFirstStep: true,
        todayHasCue: true,
        previousVerdict: true,
        warmupUsed: true,
        ipsThisMonth: true,
      );
      expect(
        currentStage(stages, all, _manual.toSet(), windows: true),
        stages.length,
      );
      // Одной ручной отметки не хватает — путь на последнем этапе.
      expect(
        currentStage(
          stages,
          all,
          _manual.where((m) => m != 'own.month').toSet(),
          windows: true,
        ),
        stages.length - 1,
      );
    });
  });

  group('stepProgress', () {
    test('шаги с порогом-числом', () {
      const f = AdoptionFacts(
        activeDirections: 1,
        checkinMornings: 4,
        causeEpisodes: 3,
        frogDays: 3,
        strategyEpisodes: 1,
      );
      expect(stepProgress('setup.dirs', f), '1 из 2');
      expect(stepProgress('observe.checkin', f), '4 утра из 7');
      expect(stepProgress('observe.causes', f), '3 из 5');
      expect(stepProgress('observe.frog', f), '3 дня из 7');
      expect(stepProgress('exp.strategies', f), '1 из 3');
    });

    test('остальные шаги — null', () {
      for (final id in [
        'setup.cats',
        'setup.windows',
        'exp.take',
        'plan.warmup',
        'observe.nofix',
      ]) {
        expect(stepProgress(id, const AdoptionFacts()), isNull, reason: id);
      }
    });

    test('счёт не выходит за порог; склонение утр/дней', () {
      expect(
        stepProgress('observe.causes', const AdoptionFacts(causeEpisodes: 9)),
        '5 из 5',
      );
      String mornings(int n) =>
          stepProgress('observe.checkin', AdoptionFacts(checkinMornings: n))!;
      expect(mornings(1), '1 утро из 7');
      expect(mornings(5), '5 утр из 7');
      String days(int n) =>
          stepProgress('observe.frog', AdoptionFacts(frogDays: n))!;
      expect(days(1), '1 день из 7');
      expect(days(5), '5 дней из 7');
    });

    test('английский', () {
      S.lang = AppLanguage.en;
      expect(
        stepProgress('observe.checkin', const AdoptionFacts(checkinMornings: 4)),
        '4 mornings of 7',
      );
      expect(
        stepProgress('observe.causes', const AdoptionFacts(causeEpisodes: 3)),
        '3 of 5',
      );
    });
  });

  group('AdoptionFacts.collect', () {
    // Среда, 4 ноября 2026; окно «7 дней» — с 29 октября по 4 ноября.
    final now = DateTime(2026, 11, 4, 10);
    DateTime d(int m, int day) => DateTime(2026, m, day);

    PomoSession session(DateTime date, {bool frog = false, bool manual = false}) =>
        PomoSession(
          id: '${date.month}-${date.day}-$frog$manual',
          start: DateTime(date.year, date.month, date.day, 9),
          minutes: 25,
          category: 'работа',
          task: 'задача',
          frog: frog,
          manual: manual,
        );

    Episode episode(String id, DateTime date, {Cause? cause, StrategyKind? s}) =>
        Episode(
          id: id,
          at: DateTime(date.year, date.month, date.day, 11),
          source: EpisodeSource.idle,
          cause: cause,
          strategy: s,
        );

    test('считает окно в 7 логических дней', () {
      final days = [
        DayLog(
          date: d(11, 4),
          goal: 8,
          sessions: [session(d(11, 4), frog: true)],
          checkIn: const CheckIn(sleep: 4),
          episodes: [
            episode('a', d(11, 4), cause: Cause.big),
            episode('b', d(11, 4), cause: Cause.tired, s: StrategyKind.warmup),
            episode('c', d(11, 4)),
          ],
        ),
        DayLog(
          date: d(11, 2),
          goal: 8,
          // Ручная отметка 🐸 за помидор не считается.
          sessions: [session(d(11, 2), frog: true, manual: true)],
          checkIn: const CheckIn(energy: 3),
        ),
        DayLog(
          date: d(10, 29),
          goal: 8,
          sessions: [session(d(10, 29), frog: true)],
          checkIn: const CheckIn(sleep: 2),
          ips: const [3, 3, 3, 3, 3, 3, 3, 3, 3],
        ),
        // За окном: ничего не должно попасть в «7 дней».
        DayLog(
          date: d(10, 28),
          goal: 8,
          sessions: [session(d(10, 28), frog: true)],
          checkIn: const CheckIn(sleep: 5),
          episodes: [episode('old', d(10, 28), cause: Cause.big)],
        ),
      ];
      final f = AdoptionFacts.collect(now: now, days: days);
      expect(f.checkinMornings, 2); // 4 ноября и 29 октября; энергия — не сон
      expect(f.frogDays, 2); // 4 ноября и 29 октября
      expect(f.causeEpisodes, 2);
      expect(f.strategyEpisodes, 1);
      expect(f.warmupUsed, isTrue);
      expect(f.ipsThisMonth, isFalse); // шкала была в октябре
    });

    test('эпизод в 00:30 относится к вчерашним суткам', () {
      // 5 ноября 00:30 — ещё 4 ноября: окно «7 дней» заканчивается 4-м.
      final f = AdoptionFacts.collect(
        now: DateTime(2026, 11, 5, 0, 30),
        days: [
          DayLog(
            date: d(11, 4),
            goal: 8,
            sessions: const [],
            checkIn: const CheckIn(sleep: 3),
          ),
        ],
      );
      expect(f.checkinMornings, 1);
    });

    test('шкала в этом месяце', () {
      final f = AdoptionFacts.collect(
        now: now,
        days: [
          DayLog(
            date: d(11, 1),
            goal: 8,
            sessions: const [],
            ips: const [1, 2, 3, 4, 5, 1, 2, 3, 4],
          ),
        ],
      );
      expect(f.ipsThisMonth, isTrue);
    });

    test('направления, задачи, спринты, настройки', () {
      Direction dir(String id, DirectionStatus st, List<String> cats) =>
          Direction(id: id, name: id, status: st, categories: cats);
      Milestone ms(String dirId, int i) =>
          Milestone(id: '$dirId$i', directionId: dirId, title: 'в$i', order: i);
      final f = AdoptionFacts.collect(
        now: now,
        directions: [
          dir('a', DirectionStatus.active, ['работа']),
          dir('b', DirectionStatus.active, const []),
          // Пауза в подсчёте активных не участвует.
          dir('c', DirectionStatus.paused, const []),
        ],
        milestones: [
          for (var i = 0; i < 3; i++) ms('a', i),
          ms('b', 0),
        ],
        todo: const [
          PomoTask(
            description: 'x',
            category: 'работа',
            durationMinutes: 25,
            firstStep: '  ',
            cue: 'после завтрака',
          ),
        ],
        sprint: Sprint(
          id: '2026-W45',
          start: _monday,
          goal: 40,
          experiment: Experiment(
            hypothesis: 'h',
            strategy: StrategyKind.firstStep,
            metric: InsightMetric.firstStart,
          ),
        ),
        previous: Sprint(
          id: '2026-W44',
          start: _monday,
          goal: 40,
          experiment: Experiment(
            hypothesis: 'h',
            strategy: StrategyKind.firstStep,
            metric: InsightMetric.firstStart,
            verdict: Verdict.works,
          ),
        ),
        settings: AppSettings.fromJson({
          'sessionWindows': ['10:00-13:00', 'мусор'],
          'aiKey': ' key ',
        }, fallbackPath: '.'),
        hasDistractMarks: true,
      );
      expect(f.activeDirections, 2);
      expect(f.directionsWithCategories, 1);
      expect(f.directionsWithLadder, 1);
      expect(f.todayHasFirstStep, isFalse); // одни пробелы
      expect(f.todayHasCue, isTrue);
      expect(f.hasExperiment, isTrue);
      expect(f.previousVerdict, isTrue);
      expect(f.hasSessionWindows, isTrue);
      expect(f.aiKeySet, isTrue);
      expect(f.hasDistractMarks, isTrue);
    });

    test('без источников — пустые факты', () {
      final f = AdoptionFacts.collect(now: now);
      for (final entry in _done.entries) {
        expect(stepDone(entry.key, f, {}), isFalse, reason: entry.key);
      }
    });
  });

  group('настройки справки', () {
    test('старый settings.json читается: ничего не отмечено, справка не видена', () {
      final s = AppSettings.fromJson(const {}, fallbackPath: '.');
      expect(s.helpChecks, isEmpty);
      expect(s.helpSeen, 0);
    });

    test('helpChecks и helpSeen переживают круг JSON', () {
      final s = AppSettings.fromJson(const {}, fallbackPath: '.').copyWith(
        helpChecks: ['exp.read'],
        helpSeen: 1,
      );
      final back = AppSettings.fromJson(s.toJson(), fallbackPath: '.');
      expect(back.helpChecks, ['exp.read']);
      expect(back.helpSeen, 1);
      expect(back, s);
    });
  });
}

final _monday = DateTime(2026, 11, 2);
