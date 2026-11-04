import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

import '../app/strings.dart';
import '../core/failure.dart';
import '../domain/entities/app_settings.dart';
import '../domain/entities/episode.dart';
import '../domain/entities/experiment.dart';

typedef Reframe = ({String pattern, String question, String alternative});
typedef AiReview = ({WeekReview review, Experiment? experiment});

/// Паттерны мышления, которые знает промт reframe; всё прочее → `none`.
const thinkingPatterns = [
  'all_or_nothing',
  'catastrophizing',
  'should',
  'mind_reading',
  'discounting',
  'overgeneralizing',
  'none',
];

/// DeepSeek в трёх фиксированных местах сценария. Ответ модели не попадает
/// в данные, пока его не проверили [parseFirstSteps]/[parseReframe]/[parseReview].
class AiService {
  AiService(this._settings, {http.Client? client, this.onConsent})
    : _client = client ?? http.Client();

  final AppSettings Function() _settings;
  final http.Client _client;

  /// Сохраняет `aiConsent = true` (main пишет его через SettingsCubit).
  final Future<void> Function()? onConsent;

  static final endpoint = Uri.https('api.deepseek.com', '/chat/completions');
  static const timeout = Duration(seconds: 30);

  bool get available {
    final s = _settings();
    return s.aiEnabled && s.aiKey.trim().isNotEmpty;
  }

  bool get consented => _settings().aiConsent;

  Future<void> grantConsent() async => onConsent?.call();

  /// Проверка ключа: без `response_format`, один токен. Включать «Подсказки»
  /// для этого не нужно — ключ проверяют до включения.
  Future<Either<Failure, Unit>> ping() async {
    if (_settings().aiKey.trim().isEmpty || !consented) {
      return Either.left(AiFailure(S.aiUnavailable));
    }
    final result = await _post(
      [
        {'role': 'user', 'content': 'ping'},
      ],
      maxTokens: 1,
      json: false,
    );
    return result.map((_) => unit);
  }

  Future<Either<Failure, List<String>>> firstSteps({
    required String task,
    String category = '',
    String direction = '',
    String milestone = '',
    Cause? cause,
    String thought = '',
  }) async {
    final raw = await _chat(
      _firstStepsPrompt.replaceAll('{language}', _language),
      _compact({
        'task': task,
        'category': category,
        'direction': direction,
        'milestone': milestone,
        'cause': cause?.name ?? '',
        'thought': thought,
      }),
      300,
    );
    return raw.flatMap(parseFirstSteps);
  }

  Future<Either<Failure, Reframe>> reframe({
    required String thought,
    Cause? cause,
    String task = '',
  }) async {
    final raw = await _chat(
      _reframePrompt.replaceAll('{language}', _language),
      _compact({'thought': thought, 'cause': cause?.name ?? '', 'task': task}),
      300,
    );
    return raw.flatMap(parseReframe);
  }

  Future<Either<Failure, AiReview>> weeklyReview(
    Map<String, Object?> payload,
  ) async {
    final system = _reviewPrompt
        .replaceAll('{language}', _language)
        .replaceAll(
          '{strategies}',
          StrategyKind.values.map((k) => k.name).join(', '),
        )
        .replaceAll(
          '{metrics}',
          InsightMetric.values.map((m) => m.name).join(', '),
        );
    final raw = await _chat(system, jsonEncode(payload), 900);
    return raw.flatMap(parseReview);
  }

  String get _language => S.lang == AppLanguage.ru ? 'Russian' : 'English';

  /// Пустые поля не отправляем: меньше токенов и меньше лишнего наружу.
  static String _compact(Map<String, String> input) => jsonEncode({
    for (final e in input.entries)
      if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
  });

  /// JSON-режим DeepSeek иногда отдаёт пустой content при finish_reason: stop
  /// — так написано в их доках; один повтор, потом честная ошибка.
  Future<Either<Failure, String>> _chat(
    String system,
    String user,
    int maxTokens,
  ) async {
    if (!available || !consented) {
      return Either.left(AiFailure(S.aiUnavailable));
    }
    final messages = [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await _post(messages, maxTokens: maxTokens, json: true);
      final failure = result.fold((f) => f, (_) => null);
      if (failure != null) return Either.left(failure);
      final content = result.getOrElse((_) => '');
      if (content.trim().isNotEmpty) return Either.right(content);
    }
    return Either.left(AiFailure(S.aiEmpty));
  }

  Future<Either<Failure, String>> _post(
    List<Map<String, String>> messages, {
    required int maxTokens,
    required bool json,
  }) async {
    final s = _settings();
    final body = {
      'model': s.aiModel.trim().isEmpty
          ? AppSettings.defaultAiModel
          : s.aiModel.trim(),
      'messages': messages,
      if (json) 'response_format': {'type': 'json_object'},
      'thinking': {'type': 'disabled'},
      'max_tokens': maxTokens,
      'stream': false,
    };
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer ${s.aiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception {
      // Нет сети, DNS, таймаут — для пользователя одно и то же.
      return Either.left(AiFailure(S.aiError));
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        return Either.left(AiFailure(S.aiBadKey));
      case 402:
        return Either.left(AiFailure(S.aiNoBalance));
      case 429:
        return Either.left(AiFailure(S.aiBusy));
      case 400 || 404 || 422:
        return Either.left(AiFailure(S.aiRejected));
      default:
        return Either.left(AiFailure(S.aiError));
    }
    try {
      // bodyBytes, а не body: без charset в заголовке http читает latin1
      // и кириллица в ответе превращается в мусор.
      final envelope = jsonDecode(utf8.decode(response.bodyBytes));
      if (envelope case {
        'choices': [{'message': final Map<String, dynamic> message}, ...],
      }) {
        final content = message['content'];
        return Either.right(content is String ? content : '');
      }
    } on FormatException {
      // Сломанный конверт — как недоступный сервер.
    }
    return Either.left(AiFailure(S.aiError));
  }

  static const _firstStepsPrompt =
      'You help a person start a task they keep putting off. Suggest exactly 3 first steps.\n'
      'Each step is one concrete physical action that takes under 5 minutes, starts with a verb,\n'
      'is at most 80 characters, and is specific to THIS task (name the file, page, tool or person\n'
      'when the task implies one). No advice, no motivation, no plan of the whole task.\n'
      'If the input suggests a crisis or self-harm, set "concern" to true and return no steps.\n'
      'Respond in {language}. Output only json, for example:\n'
      '{"steps": ["Open the Stripe dashboard → Webhooks", "Copy the endpoint URL into .env", "Write one test request in curl"], "concern": false}';

  static const _reframePrompt =
      'You help a person check one unhelpful thought that stops them from starting a task,\n'
      'using a cognitive-behavioral approach. You are not a therapist and you do not diagnose.\n'
      'Pick the closest thinking pattern from: all_or_nothing, catastrophizing, should,\n'
      'mind_reading, discounting, overgeneralizing, none.\n'
      'Write one short Socratic question (max 100 characters) that tests the thought against facts,\n'
      'and one balanced alternative thought in the first person (max 140 characters) — realistic,\n'
      'not cheerful.\n'
      'If the text suggests a crisis or self-harm, set "concern" to true and leave the other fields empty.\n'
      'Respond in {language}. Output only json, for example:\n'
      '{"pattern": "all_or_nothing", "question": "What would a good-enough first version look like?", "alternative": "A rough first version is a normal step; I can improve it tomorrow.", "concern": false}';

  static const _reviewPrompt =
      "You analyse one week of a person's self-tracking about procrastination. The data is\n"
      'aggregated; "baseline" is their first observation week. Numbers are small and noisy:\n'
      'state a pattern only when the data shows it, and quote the numbers as evidence.\n'
      'No diagnoses, no praise, no moralizing.\n'
      'Return:\n'
      '- "summary": 2–3 sentences about the week;\n'
      '- "patterns": up to 3 items {"text", "evidence"};\n'
      '- "experiment" for next week: "strategy" strictly one of [{strategies}], "metric" strictly\n'
      '  one of [{metrics}], "hypothesis" in the form "If …, then …" (max 140 characters).\n'
      '  Prefer the strategy that worked best for the most frequent cause. If last week\'s\n'
      '  experiment has verdict "works", you may keep it.\n'
      'If the notes suggest a crisis or self-harm, set "concern" to true.\n'
      'Respond in {language}. Output only json, for example:\n'
      '{"summary": "…", "patterns": [{"text": "…", "evidence": "…"}], "experiment": {"strategy": "firstStep", "metric": "firstStart", "hypothesis": "If my frog has a first step, then I start it earlier"}, "concern": false}';
}

// ---------------------------------------------------------------------------
// Проверка ответа. Всё, чего нет в схеме, выбрасывается; не прошло — ошибка,
// и вызывающий остаётся на запасном варианте по правилам.
// ---------------------------------------------------------------------------

Either<Failure, List<String>> parseFirstSteps(String raw) {
  final map = _object(raw);
  if (map == null) return Either.left(AiFailure(S.aiError));
  if (_concern(map)) return Either.left(AiConcern(S.aiConcern));
  final steps = map['steps'];
  if (steps is! List) return Either.left(AiFailure(S.aiError));
  final result = [
    for (final s in steps)
      if (s is String && s.trim().isNotEmpty) _cut(s, 80),
  ].take(3).toList(growable: false);
  if (result.isEmpty) return Either.left(AiFailure(S.aiError));
  return Either.right(result);
}

Either<Failure, Reframe> parseReframe(String raw) {
  final map = _object(raw);
  if (map == null) return Either.left(AiFailure(S.aiError));
  if (_concern(map)) return Either.left(AiConcern(S.aiConcern));
  final pattern = map['pattern'];
  final question = map['question'];
  final alternative = map['alternative'];
  if (!_stringOrNull(pattern) ||
      !_stringOrNull(question) ||
      !_stringOrNull(alternative)) {
    return Either.left(AiFailure(S.aiError));
  }
  final q = _cut(question as String? ?? '', 100);
  final a = _cut(alternative as String? ?? '', 140);
  if (q.isEmpty && a.isEmpty) return Either.left(AiFailure(S.aiError));
  final p = (pattern as String? ?? '').trim();
  return Either.right((
    pattern: thinkingPatterns.contains(p) ? p : 'none',
    question: q,
    alternative: a,
  ));
}

Either<Failure, AiReview> parseReview(String raw) {
  final map = _object(raw);
  if (map == null) return Either.left(AiFailure(S.aiError));
  if (_concern(map)) return Either.left(AiConcern(S.aiConcern));
  final summary = map['summary'];
  final patterns = map['patterns'];
  final experiment = map['experiment'];
  if (summary is! String || summary.trim().isEmpty) {
    return Either.left(AiFailure(S.aiError));
  }
  if (patterns != null && patterns is! List) {
    return Either.left(AiFailure(S.aiError));
  }
  final parsed = <({String text, String evidence})>[
    for (final p in patterns as List? ?? const [])
      if (p case {'text': final String text} when text.trim().isNotEmpty)
        (
          text: _cut(text, 140),
          evidence: p['evidence'] is String
              ? _cut(p['evidence'] as String, 120)
              : '',
        ),
  ];
  return Either.right((
    review: WeekReview(
      at: clock.now(),
      summary: _cut(summary, 400),
      patterns: parsed.take(3).toList(growable: false),
    ),
    experiment: _experiment(experiment),
  ));
}

/// Неизвестный способ/метрика или пустая гипотеза — эксперимента нет,
/// остальной разбор годится. `baseline` подставляет экран из своих цифр.
Experiment? _experiment(Object? raw) {
  if (raw case {
    'strategy': final String strategy,
    'metric': final String metric,
    'hypothesis': final String hypothesis,
  } when hypothesis.trim().isNotEmpty) {
    final kind = StrategyKind.values.asNameMap()[strategy.trim()];
    final m = InsightMetric.values.asNameMap()[metric.trim()];
    if (kind == null || m == null) return null;
    return Experiment(
      hypothesis: _cut(hypothesis, 140),
      strategy: kind,
      metric: m,
    );
  }
  return null;
}

Map<String, dynamic>? _object(String raw) {
  try {
    final decoded = jsonDecode(raw.trim());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Сомнение трактуем в сторону осторожности: и `true`, и `"true"`.
bool _concern(Map<String, dynamic> map) {
  final c = map['concern'];
  return c == true || (c is String && c.trim().toLowerCase() == 'true');
}

bool _stringOrNull(Object? v) => v == null || v is String;

/// Обрезка по символам (runes), чтобы не разрезать эмодзи пополам.
String _cut(String s, int max) {
  final text = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  final runes = text.runes;
  if (runes.length <= max) return text;
  return String.fromCharCodes(runes.take(max)).trimRight();
}
