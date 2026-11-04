import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/insights.dart';
import 'package:pomodoro_tracker/services/ai_service.dart';

AppSettings aiSettings({
  bool enabled = true,
  String key = 'test-key',
  bool consent = true,
}) => AppSettings.fromJson(
  const {},
  fallbackPath: '.',
).copyWith(aiEnabled: enabled, aiKey: key, aiConsent: consent);

/// Ответ DeepSeek в формате OpenAI с заданным content.
http.Response completion(String? content, {String finish = 'stop'}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'id': 'x',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': content},
              'finish_reason': finish,
            },
          ],
        }),
      ),
      200,
      // Без charset: http по умолчанию читал бы latin1.
      headers: {'content-type': 'application/json'},
    );

/// Сервис на MockClient: каждый запрос попадает в [requests], ответ — из [reply].
({AiService ai, List<http.Request> requests}) mockAi(
  http.Response Function(http.Request request) reply, {
  AppSettings? settings,
}) {
  final requests = <http.Request>[];
  final ai = AiService(
    () => settings ?? aiSettings(),
    client: MockClient((request) async {
      requests.add(request);
      return reply(request);
    }),
  );
  return (ai: ai, requests: requests);
}

Map<String, dynamic> bodyOf(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;

/// Все строки JSON — и ключи, и значения.
Iterable<String> allStrings(Object? node) sync* {
  if (node is String) {
    yield node;
  } else if (node is Map) {
    for (final e in node.entries) {
      yield '${e.key}';
      yield* allStrings(e.value);
    }
  } else if (node is List) {
    for (final v in node) {
      yield* allStrings(v);
    }
  }
}

const _steps =
    '{"steps": ["Открыть dashboard Stripe", "Скопировать URL", "Написать curl"], "concern": false}';

void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  test(
    'настройки ИИ: старый settings.json без полей и круг toJson/fromJson',
    () {
      final old = AppSettings.fromJson(const {
        'dailyGoal': 6,
      }, fallbackPath: '.');
      expect(old.aiEnabled, isFalse);
      expect(old.aiKey, '');
      expect(old.aiModel, 'deepseek-flash');
      expect(old.aiConsent, isFalse);
      expect(AiService(() => old).available, isFalse);
      final set = old.copyWith(
        aiEnabled: true,
        aiKey: 'k',
        aiModel: 'deepseek-v4-flash',
        aiConsent: true,
      );
      expect(AppSettings.fromJson(set.toJson(), fallbackPath: '.'), set);
      expect(
        AppSettings.fromJson(const {'aiModel': ' '}, fallbackPath: '.').aiModel,
        'deepseek-flash',
      );
    },
  );

  group('запрос', () {
    test(
      'firstSteps: модель, json_object, thinking disabled, max_tokens, Bearer',
      () async {
        final m = mockAi((_) => completion(_steps));
        final result = await m.ai.firstSteps(
          task: 'Подключить webhook',
          category: 'работа',
          cause: Cause.unclear,
        );
        expect(result.getOrElse((_) => []), hasLength(3));
        expect(m.requests, hasLength(1));
        final r = m.requests.single;
        expect(r.method, 'POST');
        expect(r.url.toString(), 'https://api.deepseek.com/chat/completions');
        expect(r.headers['Authorization'], 'Bearer test-key');
        final body = bodyOf(r);
        expect(body['model'], 'deepseek-flash');
        expect(body['response_format'], {'type': 'json_object'});
        expect(body['thinking'], {'type': 'disabled'});
        expect(body['max_tokens'], 300);
        expect(body['stream'], false);
        final messages = body['messages'] as List;
        expect(messages[0]['role'], 'system');
        expect(messages[0]['content'], contains('Respond in Russian'));
        expect(messages[0]['content'], contains('json'));
        // Пустые поля не уходят.
        expect(jsonDecode(messages[1]['content'] as String), {
          'task': 'Подключить webhook',
          'category': 'работа',
          'cause': 'unclear',
        });
      },
    );

    test('язык и модель берутся из настроек', () async {
      S.lang = AppLanguage.en;
      final m = mockAi(
        (_) => completion(
          '{"pattern": "should", "question": "Q?", "alternative": "A.", "concern": false}',
        ),
        settings: aiSettings().copyWith(aiModel: 'deepseek-v4-flash'),
      );
      await m.ai.reframe(thought: 'надо идеально', cause: Cause.perfect);
      final body = bodyOf(m.requests.single);
      expect(body['model'], 'deepseek-v4-flash');
      expect(body['max_tokens'], 300);
      expect(
        (body['messages'] as List)[0]['content'],
        contains('Respond in English'),
      );
      expect(jsonDecode((body['messages'] as List)[1]['content'] as String), {
        'thought': 'надо идеально',
        'cause': 'perfect',
      });
    });

    test('weeklyReview: 900 токенов, в промте все способы и метрики', () async {
      final m = mockAi((_) => completion('{"summary": "Неделя ровная."}'));
      await m.ai.weeklyReview({'week': '2026-W45'});
      final body = bodyOf(m.requests.single);
      expect(body['max_tokens'], 900);
      final system = (body['messages'] as List)[0]['content'] as String;
      for (final k in StrategyKind.values) {
        expect(system, contains(k.name));
      }
      expect(
        system,
        contains(InsightMetric.values.map((m) => m.name).join(', ')),
      );
      expect(system, isNot(contains('{strategies}')));
      expect(system, isNot(contains('{metrics}')));
    });

    test('ping: без response_format, «ping», max_tokens 1', () async {
      final m = mockAi((_) => completion('p'));
      final result = await m.ai.ping();
      expect(result.isRight(), isTrue);
      final body = bodyOf(m.requests.single);
      expect(body.containsKey('response_format'), isFalse);
      expect(body['max_tokens'], 1);
      expect(body['thinking'], {'type': 'disabled'});
      expect(body['messages'], [
        {'role': 'user', 'content': 'ping'},
      ]);
    });

    test('без ключа, выключено или без согласия — ни одного запроса', () async {
      for (final settings in [
        aiSettings(key: ''),
        aiSettings(enabled: false),
        aiSettings(consent: false),
      ]) {
        final m = mockAi((_) => completion(_steps), settings: settings);
        expect(m.ai.available, settings.aiEnabled && settings.aiKey.isNotEmpty);
        final result = await m.ai.firstSteps(task: 'задача');
        expect(result.isLeft(), isTrue);
        expect(m.requests, isEmpty);
      }
    });
  });

  group('ответ', () {
    test('пустой content → ровно один повтор, затем понятная ошибка', () async {
      final m = mockAi((_) => completion(''));
      final result = await m.ai.firstSteps(task: 'задача');
      expect(m.requests, hasLength(2));
      final failure = result.getLeft().toNullable();
      expect(failure, isA<AiFailure>());
      expect(failure!.message, S.aiEmpty);
    });

    test('null content тоже пустой; второй ответ годится', () async {
      var n = 0;
      final m = mockAi((_) => n++ == 0 ? completion(null) : completion(_steps));
      final result = await m.ai.firstSteps(task: 'задача');
      expect(m.requests, hasLength(2));
      expect(result.getOrElse((_) => []), hasLength(3));
    });

    for (final (code, message) in [
      (401, () => S.aiBadKey),
      (402, () => S.aiNoBalance),
      (429, () => S.aiBusy),
      (500, () => S.aiError),
      (503, () => S.aiError),
      (400, () => S.aiRejected),
    ]) {
      test('HTTP $code → своё сообщение, без повтора', () async {
        final m = mockAi((_) => http.Response('{"error": {}}', code));
        final result = await m.ai.firstSteps(task: 'задача');
        expect(m.requests, hasLength(1));
        final failure = result.getLeft().toNullable();
        expect(failure, isA<AiFailure>());
        expect(failure!.message, message());
      });
    }

    test('ping с неверным ключом → «Ключ не подходит»', () async {
      final m = mockAi((_) => http.Response('', 401));
      final result = await m.ai.ping();
      expect(result.getLeft().toNullable()?.message, S.aiBadKey);
    });

    test('сеть недоступна → «DeepSeek не ответил», без исключения', () async {
      final ai = AiService(
        aiSettings,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final result = await ai.reframe(thought: 'мысль');
      expect(result.getLeft().toNullable()?.message, S.aiError);
    });

    test('таймаут 30 с → «DeepSeek не ответил»', () {
      fakeAsync((async) {
        final ai = AiService(
          aiSettings,
          client: MockClient((_) => Completer<http.Response>().future),
        );
        Either<Failure, List<String>>? result;
        ai.firstSteps(task: 'задача').then((r) => result = r);
        async.elapse(const Duration(seconds: 29));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(result?.getLeft().toNullable()?.message, S.aiError);
      });
    });

    test(
      'сломанный конверт или не JSON в content → ошибка, не мусор',
      () async {
        for (final response in [
          http.Response('<html>', 200),
          http.Response('{"choices": []}', 200),
          completion('Вот три шага: ...'),
          completion('{"steps": "один шаг"}'),
          completion('["a", "b"]'),
        ]) {
          final m = mockAi((_) => response);
          final result = await m.ai.firstSteps(task: 'задача');
          expect(result.getLeft().toNullable(), isA<AiFailure>());
        }
      },
    );

    test('кириллица в ответе без charset читается как UTF-8', () async {
      final m = mockAi((_) => completion(_steps));
      final steps = (await m.ai.firstSteps(
        task: 'задача',
      )).getOrElse((_) => []);
      expect(steps.first, 'Открыть dashboard Stripe');
    });

    test('concern: true → AiConcern во всех трёх вызовах', () async {
      final m = mockAi(
        (_) =>
            completion('{"steps": ["шаг"], "concern": true, "summary": "x"}'),
      );
      final steps = await m.ai.firstSteps(task: 'задача');
      final reframe = await m.ai.reframe(thought: 'мысль');
      final review = await m.ai.weeklyReview(const {});
      for (final result in [steps, reframe, review]) {
        final failure = result.getLeft().toNullable();
        expect(failure, isA<AiConcern>());
        expect(failure!.message, S.aiConcern);
      }
    });
  });

  group('разбор', () {
    test('firstSteps: до 3 шагов, ≤80 символов, пустые выброшены', () {
      final long = 'О' * 120;
      final result = parseFirstSteps(
        jsonEncode({
          'steps': ['', '  ', long, 42, 'Шаг два', 'Шаг три', 'Шаг четыре'],
          'concern': false,
          'extra': 'лишнее',
        }),
      ).getOrElse((_) => []);
      expect(result, ['О' * 80, 'Шаг два', 'Шаг три']);
    });

    test('firstSteps: нет ни одного шага → ошибка', () {
      expect(parseFirstSteps('{"steps": []}').isLeft(), isTrue);
      expect(parseFirstSteps('{}').isLeft(), isTrue);
    });

    test('reframe: неизвестный pattern → none, длины режутся', () {
      final r = parseReframe(
        jsonEncode({
          'pattern': 'fortune_telling',
          'question': 'В' * 150,
          'alternative': 'А' * 200,
          'concern': false,
        }),
      ).getOrElse((_) => throw StateError('left'));
      expect(r.pattern, 'none');
      expect(r.question, 'В' * 100);
      expect(r.alternative, 'А' * 140);
      final known = parseReframe(
        '{"pattern": "catastrophizing", "question": "Q?", "alternative": "A."}',
      ).getOrElse((_) => throw StateError('left'));
      expect(known.pattern, 'catastrophizing');
    });

    test('reframe: неверные типы или пустые поля → ошибка', () {
      expect(parseReframe('{"pattern": 1, "question": "Q"}').isLeft(), isTrue);
      expect(
        parseReframe('{"question": "", "alternative": ""}').isLeft(),
        isTrue,
      );
      expect(parseReframe('не json').isLeft(), isTrue);
    });

    test('review: обрезка, до 3 закономерностей, валидный эксперимент', () {
      final r = parseReview(
        jsonEncode({
          'summary': 'С' * 500,
          'patterns': [
            {'text': 'Т' * 200, 'evidence': 'Д' * 200},
            {'text': '', 'evidence': 'пусто'},
            'строка',
            {'text': 'два'},
            {'text': 'три', 'evidence': 'e'},
            {'text': 'четыре', 'evidence': 'e'},
          ],
          'experiment': {
            'strategy': 'firstStep',
            'metric': 'firstStart',
            'hypothesis': 'Если ' * 50,
          },
        }),
      ).getOrElse((_) => throw StateError('left'));
      expect(r.review.summary.runes.length, 400);
      expect(r.review.patterns, hasLength(3));
      expect(r.review.patterns.first.text, 'Т' * 140);
      expect(r.review.patterns.first.evidence, 'Д' * 120);
      expect(r.review.patterns[1], (text: 'два', evidence: ''));
      expect(r.experiment?.strategy, StrategyKind.firstStep);
      expect(r.experiment?.metric, InsightMetric.firstStart);
      expect(r.experiment!.hypothesis.runes.length, lessThanOrEqualTo(140));
      expect(r.experiment!.baseline, isNull);
    });

    test('review: неизвестный strategy или metric → experiment null', () {
      for (final exp in [
        {'strategy': 'meditate', 'metric': 'idle', 'hypothesis': 'Если…'},
        {'strategy': 'warmup', 'metric': 'mood', 'hypothesis': 'Если…'},
        {'strategy': 'warmup', 'metric': 'idle', 'hypothesis': ''},
        {'strategy': 3, 'metric': 'idle', 'hypothesis': 'Если…'},
      ]) {
        final r = parseReview(
          jsonEncode({'summary': 'Итог.', 'experiment': exp}),
        ).getOrElse((_) => throw StateError('left'));
        expect(r.review.summary, 'Итог.');
        expect(r.experiment, isNull);
      }
    });

    test('review: без summary или patterns не список → ошибка', () {
      expect(parseReview('{"patterns": []}').isLeft(), isTrue);
      expect(parseReview('{"summary": "x", "patterns": "y"}').isLeft(), isTrue);
    });
  });

  group('reviewPayload', () {
    const secretApp = 'YouTube — секретное окно';
    const secretTask = 'Секретное описание задачи';
    const secretCategory = 'секретная-категория';
    final monday = DateTime(2026, 11, 2);

    Episode ep(String id, DateTime at, {String thought = '', Cause? cause}) =>
        Episode(
          id: id,
          at: at,
          source: EpisodeSource.distract,
          taskId: 'task-id',
          task: secretTask,
          category: secretCategory,
          app: secretApp,
          cause: cause,
          strategy: StrategyKind.firstStep,
          thought: thought,
          fact: 'секретный факт',
          alt: 'секретная альтернатива',
        );

    List<DayLog> days() => [
      for (var i = 0; i < 14; i++)
        DayLog(
          date: DateTime(2026, 10, 26 + i),
          goal: 8,
          sessions: [
            PomoSession(
              id: 's$i',
              start: DateTime(2026, 10, 26 + i, 10),
              minutes: 25,
              category: secretCategory,
              task: secretTask,
              delayMinutes: 3,
            ),
          ],
          episodes: [
            ep(
              'a$i',
              DateTime(2026, 10, 26 + i, 9),
              thought: 'мысль $i ${'м' * 200}',
              cause: Cause.perfect,
            ),
            ep('b$i', DateTime(2026, 10, 26 + i, 11), cause: Cause.unclear),
          ],
          notes: const ['секретная заметка «на чём встал»'],
          checkIn: CheckIn(sleep: i.isEven ? 5 : 1, energy: 3),
        ),
    ];

    test('нет имён окон, описаний задач, категорий и фактов', () {
      final all = days();
      WeekInsight w(int from) => weekInsight(all.sublist(from, from + 7));
      final payload = reviewPayload(
        week: '2026-W45',
        observation: false,
        monday: monday,
        current: w(7),
        previous: w(0),
        baseline: w(0),
        days: all,
        experiment: const Experiment(
          hypothesis: 'Если есть первый шаг, то старт раньше',
          strategy: StrategyKind.firstStep,
          metric: InsightMetric.firstStart,
          baseline: 40,
        ),
        lastExperiment: const Experiment(
          hypothesis: 'Если разгон, то меньше простоя',
          strategy: StrategyKind.warmup,
          metric: InsightMetric.idle,
          baseline: 5,
        ),
      );
      // Через JSON, как уходит в API.
      final decoded = jsonDecode(jsonEncode(payload));
      final strings = allStrings(decoded).toList();
      for (final s in strings) {
        expect(s, isNot(contains('YouTube')));
        expect(s, isNot(contains('секрет')));
        expect(s, isNot(contains('Секрет')));
        expect(s, isNot(contains('task-id')));
      }
      for (final key in [
        'app',
        'task',
        'd',
        'c',
        'tid',
        'category',
        'fact',
        'alt',
      ]) {
        expect(strings, isNot(contains(key)));
      }

      final map = decoded as Map<String, dynamic>;
      expect(map['week'], '2026-W45');
      expect(map['observation'], false);
      expect(map['current']['causes'], {'perfect': 7, 'unclear': 7});
      expect(map['current']['strategies']['firstStep']['tries'], 14);
      expect(
        map['current']['metrics']['idle'],
        isNull,
      ); // 7 сессий, но первая за день
      expect(
        (map['previous']['metrics'] as Map).containsKey('deferrals'),
        isTrue,
      );
      expect(map['baseline']['metrics'], isA<Map>());
      expect(map['experiment']['verdict'], isA<String>());
      expect(map['experiment']['strategy'], 'warmup');
      expect(map['currentExperiment']['hypothesis'], startsWith('Если есть'));
      expect(map['wellbeing']['sleep'], isA<Map>());
      final thoughts = map['thoughts'] as List;
      expect(thoughts, hasLength(14));
      for (final t in thoughts) {
        expect((t['thought'] as String).runes.length, lessThanOrEqualTo(120));
        expect(t['cause'], 'perfect');
      }
      // Свежие первыми.
      expect(thoughts.first['thought'], startsWith('мысль 13'));
    });

    test('мыслей не больше 20', () {
      final many = [
        DayLog(
          date: monday,
          goal: 8,
          sessions: const [],
          episodes: [
            for (var i = 0; i < 30; i++)
              ep(
                't$i',
                monday.add(Duration(hours: 6, minutes: i)),
                thought: 'мысль $i',
              ),
          ],
        ),
      ];
      final payload = reviewPayload(
        week: '2026-W45',
        observation: true,
        monday: monday,
        current: weekInsight(many),
        previous: weekInsight(const []),
        days: many,
      );
      expect(payload['thoughts'], hasLength(20));
      expect(payload.containsKey('baseline'), isFalse);
      expect(payload.containsKey('experiment'), isFalse);
    });
  });
}
