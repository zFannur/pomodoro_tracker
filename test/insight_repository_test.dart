import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';
import 'package:pomodoro_tracker/data/json_data_repository.dart';
import 'package:pomodoro_tracker/data/vault_repositories.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

void main() {
  late Directory temp;
  late VaultStore store;
  late JsonDataRepository repo;
  final day = DateTime(2026, 11, 4);
  const answers = [3, 4, 2, 3, 3, 2, 4, 3, 3];
  const experiment = Experiment(
    hypothesis: 'С первым шагом начну раньше',
    strategy: StrategyKind.firstStep,
    metric: InsightMetric.firstStart,
    baseline: 0,
    verdict: Verdict.works,
  );
  final review = WeekReview(
    at: DateTime(2026, 11, 10, 9, 12),
    summary: 'Итог недели',
    patterns: const [(text: 'Утро помогает', evidence: '3 из 4 дней')],
  );

  JsonDataRepository fresh({bool mirror = false}) => JsonDataRepository(
    store,
    mirrorEnabled: () => mirror,
    dirProvider: () async => '${temp.path}/data',
  );
  Episode episode(String id, {DateTime? at}) => Episode(
    id: id,
    at: at ?? DateTime(2026, 11, 4, 10, 15),
    source: EpisodeSource.idle,
    taskId: 't1',
    task: 'Подключить Stripe',
    category: 'оплата',
    cause: Cause.unclear,
    strategy: StrategyKind.firstStep,
    thought: 'Надо правильно',
    fact: 'Можно проверить',
    alt: 'Начну с малого',
    app: 'YouTube',
  );
  File dataFile() => File('${temp.path}/data/data.json');
  Map<String, dynamic> readDoc() =>
      jsonDecode(dataFile().readAsStringSync()) as Map<String, dynamic>;
  Future<DayLog> readDay([JsonDataRepository? r, DateTime? date]) async =>
      (await (r ?? repo).day(date ?? day, 8)).getOrElse((f) => fail(f.message));
  Future<Sprint> readSprint([JsonDataRepository? r]) async =>
      (await (r ?? repo).current(day, 40)).getOrElse((f) => fail(f.message));

  setUp(() {
    // Все данные и зеркала теста изолированы от AppData и Obsidian.
    temp = Directory.systemTemp.createTempSync('pomo_insight_');
    store = VaultStore('${temp.path}/vault');
    repo = fresh();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('round-trip дня: эпизод, ночь 00:30, самочувствие и IPS', () async {
    final morning = episode('morning');
    final night = episode('night', at: DateTime(2026, 11, 5, 0, 30));
    expect((await repo.addEpisode(morning)).isRight(), isTrue);
    expect((await repo.addEpisode(night)).isRight(), isTrue);
    expect(
      (await repo.setCheckIn(
        day,
        const CheckIn(sleep: 4, energy: 3, mood: 5),
      )).isRight(),
      isTrue,
    );
    expect((await repo.saveIps(day, answers)).isRight(), isTrue);
    final loaded = await readDay(fresh());
    expect(loaded.episodes, [morning, night]);
    expect(loaded.checkIn, const CheckIn(sleep: 4, energy: 3, mood: 5));
    expect(loaded.ips, answers);
    expect((await readDay(fresh(), DateTime(2026, 11, 5))).episodes, isEmpty);
    final json = readDoc()['days']['2026-11-04'] as Map;
    expect(json['e'][1]['t'], '00:30');
    expect(json['e'][0], {
      'id': 'morning',
      't': '10:15',
      'src': 'idle',
      'tid': 't1',
      'd': 'Подключить Stripe',
      'c': 'оплата',
      'cause': 'unclear',
      'st': 'firstStep',
      'th': 'Надо правильно',
      'fact': 'Можно проверить',
      'alt': 'Начну с малого',
      'app': 'YouTube',
    });
    expect(json['ck'], {'sl': 4, 'en': 3, 'md': 5});
    final range = (await fresh().range(
      day,
      day,
      8,
    )).getOrElse((f) => fail(f.message));
    expect(range.single, loaded);
  });

  test('все enum эпизода пишутся по name и переживают чтение', () async {
    final episodes = [
      for (final source in EpisodeSource.values)
        episode('src-${source.name}').copyWith(source: source),
      for (final cause in Cause.values)
        episode('cause-${cause.name}').copyWith(cause: cause),
      for (final strategy in StrategyKind.values)
        episode('st-${strategy.name}').copyWith(strategy: strategy),
    ];
    for (final e in episodes) {
      expect((await repo.addEpisode(e)).isRight(), isTrue);
    }
    expect((await readDay(fresh())).episodes, episodes);
  });

  test(
    'необязательные пустые поля эпизода и эксперимента не пишутся',
    () async {
      final signal = Episode(
        id: 'quiet',
        at: DateTime(2026, 11, 4, 10),
        source: EpisodeSource.distract,
      );
      await repo.addEpisode(signal);
      expect(readDoc()['days']['2026-11-04']['e'][0], {
        'id': 'quiet',
        't': '10:00',
        'src': 'distract',
      });
      const pending = Experiment(
        hypothesis: '',
        strategy: StrategyKind.rest,
        metric: InsightMetric.idle,
      );
      await repo.saveExperiment('2026-W45', pending);
      expect(readDoc()['sprints']['2026-W45']['exp'], {
        'st': 'rest',
        'm': 'idle',
      });
      expect((await readDay(fresh())).episodes, [signal]);
      expect((await readSprint(fresh())).experiment, pending);
    },
  );

  test(
    'старый снимок журнала не затирает наблюдения после applyRemote',
    () async {
      final stale = await readDay();
      await repo.applyRemote(
        jsonEncode({
          'days': {
            '2026-11-04': {
              'goal': 8,
              'e': [
                {'id': 'remote', 't': '09:00', 'src': 'manual'},
              ],
              'ck': {'sl': 4},
              'ips': answers,
            },
          },
        }),
      );
      await repo.saveDay(stale.copyWith(notes: const ['локальная заметка']));
      final loaded = await readDay(fresh());
      expect(loaded.episodes.single.id, 'remote');
      expect(loaded.checkIn, const CheckIn(sleep: 4));
      expect(loaded.ips, answers);
      expect(readDoc()['graves'], isEmpty);
    },
  );

  test('граница 05:00 и смена месяца сохраняют логическую дату', () async {
    final night = episode('night', at: DateTime(2026, 12, 1, 4, 59));
    final morning = episode('morning', at: DateTime(2026, 12, 1, 5));
    await repo.addEpisode(night);
    await repo.addEpisode(morning);
    expect((await readDay(fresh(), DateTime(2026, 11, 30))).episodes, [night]);
    expect((await readDay(fresh(), DateTime(2026, 12, 1))).episodes, [morning]);
  });

  test('round-trip спринта: exp и ai с точными ключами', () async {
    expect(
      (await repo.saveExperiment('2026-W45', experiment)).isRight(),
      isTrue,
    );
    expect((await repo.saveReview('2026-W45', review)).isRight(), isTrue);
    final sprint = await readSprint(fresh());
    expect(sprint.experiment, experiment);
    expect(sprint.review, review);
    final json = readDoc()['sprints']['2026-W45'] as Map;
    expect(json['exp'], {
      'h': experiment.hypothesis,
      'st': 'firstStep',
      'm': 'firstStart',
      'base': 0.0,
      'v': 'works',
    });
    expect(json['ai'], {
      'at': review.at.toIso8601String(),
      'summary': review.summary,
      'p': [
        {'t': 'Утро помогает', 'e': '3 из 4 дней'},
      ],
    });
  });

  test('старый JSON без полей: дефолты и отсутствие пустых ключей', () async {
    dataFile().parent.createSync(recursive: true);
    dataFile().writeAsStringSync(
      jsonEncode({
        'days': {
          '2026-11-04': {'goal': 8, 's': []},
        },
        'sprints': {
          '2026-W45': {'goal': 40},
        },
      }),
    );
    final log = await readDay();
    expect(log.episodes, isEmpty);
    expect(log.checkIn.isEmpty, isTrue);
    expect(log.ips, isEmpty);
    final sprint = await readSprint();
    expect(sprint.experiment, isNull);
    expect(sprint.review, isNull);
    await repo.saveDay(log.copyWith(goal: 9));
    await repo.saveSprint(sprint.copyWith(goal: 41), const []);
    final doc = readDoc();
    for (final key in ['e', 'ck', 'ips']) {
      expect((doc['days']['2026-11-04'] as Map).containsKey(key), isFalse);
    }
    for (final key in ['exp', 'ai']) {
      expect((doc['sprints']['2026-W45'] as Map).containsKey(key), isFalse);
    }
  });

  test('неизвестные enum не мешают чтению эпизода', () async {
    await repo.applyRemote(
      jsonEncode({
        'days': {
          '2026-11-04': {
            'e': [
              {
                'id': 'future',
                't': '10:15',
                'src': 'future',
                'cause': 'future',
                'st': 'future',
                'd': 'снимок',
              },
            ],
          },
        },
        'sprints': {
          '2026-W45': {
            'exp': {'st': 'firstStep', 'm': 'firstStart', 'v': 'future'},
          },
        },
      }),
    );
    final loaded = (await readDay(fresh())).episodes.single;
    expect(loaded.id, 'future');
    expect(loaded.task, 'снимок');
    expect(loaded.source, isNull);
    expect(loaded.cause, isNull);
    expect(loaded.strategy, isNull);
    expect((await readSprint(fresh())).experiment?.verdict, isNull);
  });

  test(
    'неизвестные обязательные enum эксперимента дают null без падения',
    () async {
      for (final raw in [
        {'st': 'future', 'm': 'idle'},
        {'st': 'rest', 'm': 'future'},
      ]) {
        await repo.applyRemote(
          jsonEncode({
            'sprints': {
              '2026-W45': {'exp': raw},
            },
          }),
        );
        expect((await readSprint()).experiment, isNull);
      }
    },
  );

  test('saveDay старого снимка сохраняет e/ck/ips, но меняет журнал', () async {
    final stale = await readDay();
    await repo.addEpisode(episode('e'));
    await repo.setCheckIn(day, const CheckIn(sleep: 4));
    await repo.saveIps(day, answers);
    for (var i = 0; i < 2; i++) {
      await repo.saveDay(stale.copyWith(goal: 9, notes: const ['заметка']));
      final loaded = await readDay(fresh());
      expect(loaded.episodes, [episode('e')]);
      expect(loaded.checkIn, const CheckIn(sleep: 4));
      expect(loaded.ips, answers);
      expect(loaded.notes, ['заметка']);
      expect(loaded.goal, 9);
      expect(readDoc()['graves'], isEmpty);
    }
  });

  test(
    'saveDay не восстанавливает удалённые P-поля из старого снимка',
    () async {
      await repo.addEpisode(episode('e'));
      await repo.saveIps(day, answers);
      final stale = await readDay();
      await repo.deleteEpisode('e');
      await repo.saveIps(day, const []);
      await repo.saveDay(stale);
      final loaded = await readDay(fresh());
      expect(loaded.episodes, isEmpty);
      expect(loaded.ips, isEmpty);
      expect(readDoc()['graves'], contains('e'));
    },
  );

  test('saveSprint сохраняет свежие exp/ai и зеркало в обеих ветках', () async {
    repo = fresh(mirror: true);
    final stale = await readSprint();
    await repo.saveSprint(stale, const []);
    await repo.saveExperiment(stale.id, experiment);
    await repo.saveReview(stale.id, review);
    var saves = 0;
    repo.onSaved = () => saves++;
    await repo.saveSprint(stale, const []);
    expect(saves, 0);
    expect(
      store.sprintFile(stale.id).readAsStringSync(),
      contains('## Эксперимент'),
    );
    await repo.saveSprint(
      stale.copyWith(goal: 50, milestone: 'веха'),
      const [],
    );
    expect(saves, 1);
    final loaded = await readSprint(fresh());
    expect(loaded.experiment, experiment);
    expect(loaded.review, review);
    expect(loaded.goal, 50);
    expect(loaded.milestone, 'веха');
    expect(
      store.sprintFile(stale.id).readAsStringSync(),
      contains(review.summary),
    );
  });

  test('очистка эксперимента не отменяется устаревшим saveSprint', () async {
    await repo.saveExperiment('2026-W45', experiment);
    await repo.saveReview('2026-W45', review);
    final stale = await readSprint();
    await repo.saveExperiment(stale.id, null);
    await repo.saveSprint(stale.copyWith(goal: 50), const []);
    final loaded = await readSprint(fresh());
    expect(loaded.experiment, isNull);
    expect(loaded.review, review);
    expect(readDoc()['sprints']['2026-W45'], isNot(contains('exp')));
  });

  test(
    'setCheckIn объединяет утро и вечер и заменяет только данное поле',
    () async {
      await repo.setCheckIn(day, const CheckIn(sleep: 4, energy: 3));
      await repo.setCheckIn(day, const CheckIn(mood: 5));
      expect(
        (await readDay(fresh())).checkIn,
        const CheckIn(sleep: 4, energy: 3, mood: 5),
      );
      await repo.setCheckIn(day, const CheckIn(sleep: 2));
      await repo.setCheckIn(day, const CheckIn());
      expect(
        (await readDay(fresh())).checkIn,
        const CheckIn(sleep: 2, energy: 3, mood: 5),
      );
    },
  );

  test(
    'updateEpisode ищет id, сохраняет данные, неизвестный id — no-op',
    () async {
      await repo.addEpisode(episode('e'));
      final updated = episode(
        'e',
      ).copyWith(cause: Cause.big, clearStrategy: true);
      await repo.updateEpisode(updated);
      expect((await readDay(fresh())).episodes, [updated]);
      final before = dataFile().readAsStringSync();
      var saves = 0;
      repo.onSaved = () => saves++;
      await repo.updateEpisode(episode('missing'));
      await repo.deleteEpisode('missing');
      expect(dataFile().readAsStringSync(), before);
      expect(saves, 0);
    },
  );

  test('updateEpisode с новой датой переносит запись без надгробия', () async {
    await repo.addEpisode(episode('e'));
    final moved = episode('e', at: DateTime(2026, 11, 6, 0, 30));
    await repo.updateEpisode(moved);
    expect((await readDay(fresh())).episodes, isEmpty);
    expect((await readDay(fresh(), DateTime(2026, 11, 5))).episodes, [moved]);
    expect(readDoc()['graves'], isEmpty);
  });

  test(
    'deleteEpisode ставит надгробие; синк не воскрешает при любом победителе',
    () async {
      await repo.addEpisode(episode('e'));
      final remote = dataFile().readAsStringSync();
      await repo.deleteEpisode('e');
      final local = dataFile().readAsStringSync();
      final graves = readDoc()['graves'] as Map;
      expect(graves, contains('e'));
      expect(DateTime.tryParse(graves['e'] as String), isNotNull);
      for (final localWins in [true, false]) {
        final merged = mergeData(local, remote, localWins: localWins);
        await repo.applyRemote(merged);
        expect((await readDay(fresh())).episodes, isEmpty);
        expect(readDoc()['graves'], contains('e'));
      }
    },
  );

  test('параллельные первые записи не теряют эпизоды, оценки и IPS', () async {
    final results = await Future.wait([
      repo.addEpisode(episode('a')),
      repo.addEpisode(episode('b')),
      repo.setCheckIn(day, const CheckIn(sleep: 4)),
      repo.setCheckIn(day, const CheckIn(mood: 5)),
      repo.saveIps(day, answers),
      repo.saveExperiment('2026-W45', experiment),
      repo.saveReview('2026-W45', review),
    ]);
    expect(results.every((r) => r.isRight()), isTrue);
    final loaded = await readDay(fresh());
    expect(loaded.episodes.map((e) => e.id), ['a', 'b']);
    expect(loaded.checkIn, const CheckIn(sleep: 4, mood: 5));
    expect(loaded.ips, answers);
    expect((await readSprint(fresh())).review, review);
    expect((await readSprint(fresh())).experiment, experiment);
    expect(
      dataFile().parent.listSync().where((e) => e.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('прилёт синка и следующий addEpisode идут в одной очереди', () async {
    await readDay();
    final remote = jsonEncode({
      'days': {
        '2026-11-04': {
          'e': [
            {'id': 'remote', 't': '09:00', 'src': 'manual'},
          ],
        },
      },
    });
    await Future.wait([
      repo.applyRemote(remote),
      repo.addEpisode(episode('local')),
    ]);
    expect((await readDay(fresh())).episodes.map((e) => e.id), [
      'remote',
      'local',
    ]);
  });

  test('повтор addEpisode с тем же id не создаёт дубль', () async {
    await repo.addEpisode(episode('e'));
    await repo.addEpisode(episode('e'));
    expect((await readDay(fresh())).episodes, [episode('e')]);
  });

  test(
    'ошибка id спринта типизирована и не ломает следующую операцию',
    () async {
      expect((await repo.saveExperiment('bad', experiment)).isLeft(), isTrue);
      expect((await repo.addEpisode(episode('e'))).isRight(), isTrue);
      expect((await readDay(fresh())).episodes, [episode('e')]);
    },
  );

  test(
    'атомарные методы обновляют только временные зеркала дня и спринта',
    () async {
      repo = fresh(mirror: true);
      await repo.addEpisode(episode('e'));
      await repo.setCheckIn(day, const CheckIn(sleep: 4));
      var md = store.journalFile(day).readAsStringSync();
      expect(md, contains('## Самочувствие'));
      expect(md, contains('## Откладывания'));
      await repo.updateEpisode(episode('e').copyWith(thought: 'новая мысль'));
      md = store.journalFile(day).readAsStringSync();
      expect(md, contains('новая мысль'));
      await repo.deleteEpisode('e');
      expect(
        store.journalFile(day).readAsStringSync(),
        isNot(contains('## Откладывания')),
      );
      await repo.saveExperiment('2026-W45', experiment);
      await repo.saveReview('2026-W45', review);
      md = store.sprintFile('2026-W45').readAsStringSync();
      expect(md, contains('## Эксперимент'));
      expect(md, contains('## Разбор'));
      await repo.saveExperiment('2026-W45', null);
      expect(
        store.sprintFile('2026-W45').readAsStringSync(),
        isNot(contains('## Эксперимент')),
      );
    },
  );
}
