import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/insight_screen.dart';
import 'package:pomodoro_tracker/presentation/widgets/episode_sheet.dart';
import 'package:pomodoro_tracker/presentation/widgets/first_step_field.dart';
import 'package:pomodoro_tracker/services/ai_service.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

/// Сервис на MockClient с изменяемыми настройками: согласие пишется в них.
class AiHarness {
  AiHarness({
    bool enabled = true,
    String key = 'test-key',
    bool consent = true,
    required String content,
  }) : settings = AppSettings.fromJson(
         const {},
         fallbackPath: '.',
       ).copyWith(aiEnabled: enabled, aiKey: key, aiConsent: consent) {
    ai = AiService(
      () => settings,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': content},
                  'finish_reason': 'stop',
                },
              ],
            }),
          ),
          200,
        );
      }),
      onConsent: () async => settings = settings.copyWith(aiConsent: true),
    );
  }

  AppSettings settings;
  late final AiService ai;
  final requests = <http.Request>[];
}

const _stepsJson =
    '{"steps": ["Открыть dashboard", "Скопировать URL", "Написать curl"], "concern": false}';

Future<TextEditingController> pumpField(
  WidgetTester tester, {
  AiService? ai,
  bool provide = true,
}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  final field = FirstStepField(
    controller: controller,
    task: 'Подключить webhook',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: provide && ai != null
            ? RepositoryProvider.value(value: ai, child: field)
            : field,
      ),
    ),
  );
  return controller;
}

class _AiInsight extends InsightCubit {
  _AiInsight({required List<DayLog> days, required Sprint sprint})
    : super(FakeInsights(), FakeJournal(), FakeSprints(), episodeSettings) {
    emit(InsightState(status: InsightStatus.ready, days: days, sprint: sprint));
  }

  final reviews = <WeekReview>[];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> saveReview(WeekReview r) async {
    reviews.add(r);
    emit(state.copyWith(sprint: state.sprint!.copyWith(review: r)));
  }
}

final _now = DateTime(2026, 11, 4, 12);

List<DayLog> _days() => [
  // Прошлая неделя — с эпизодами: текущая уже не неделя наблюдения.
  for (var d = 26; d <= 31; d++)
    DayLog(
      date: DateTime(2026, 10, d),
      goal: 8,
      sessions: [
        PomoSession(
          id: 's$d',
          start: DateTime(2026, 10, d, 10),
          minutes: 25,
          category: 'работа',
          task: 'задача',
        ),
      ],
      episodes: [
        Episode(
          id: 'e$d',
          at: DateTime(2026, 10, d, 9),
          source: EpisodeSource.manual,
          cause: Cause.unclear,
        ),
      ],
    ),
  DayLog(date: DateTime(2026, 11, 3), goal: 8, sessions: const []),
];

void main() {
  group('FirstStepField', () {
    testWidgets('без сервиса в дереве ✨ нет', (tester) async {
      await pumpField(tester, provide: false);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });

    testWidgets('available == false — ✨ нет, запросов нет', (tester) async {
      for (final h in [
        AiHarness(enabled: false, content: _stepsJson),
        AiHarness(key: '', content: _stepsJson),
      ]) {
        expect(h.ai.available, isFalse);
        await pumpField(tester, ai: h.ai);
        expect(find.byIcon(Icons.auto_awesome), findsNothing);
        expect(h.requests, isEmpty);
      }
    });

    testWidgets('без согласия — диалог; «Отмена» не отправляет запрос', (
      tester,
    ) async {
      final h = AiHarness(consent: false, content: _stepsJson);
      await pumpField(tester, ai: h.ai);
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      expect(find.text(S.aiConsentText), findsOneWidget);
      await tester.tap(find.text(S.cancel));
      await tester.pumpAndSettle();
      expect(h.requests, isEmpty);
      expect(h.settings.aiConsent, isFalse);
    });

    testWidgets(
      '«Да, не спрашивать» → согласие, три чипа, тап заполняет поле',
      (tester) async {
        final h = AiHarness(consent: false, content: _stepsJson);
        final controller = await pumpField(tester, ai: h.ai);
        await tester.tap(find.byIcon(Icons.auto_awesome));
        await tester.pumpAndSettle();
        await tester.tap(find.text(S.aiConsentYes));
        await tester.pumpAndSettle();
        expect(h.settings.aiConsent, isTrue);
        expect(h.requests, hasLength(1));
        expect(find.byType(ActionChip), findsNWidgets(3));
        await tester.tap(find.text('Скопировать URL'));
        await tester.pumpAndSettle();
        expect(controller.text, 'Скопировать URL');
        expect(find.byType(ActionChip), findsNothing);
        // Второй раз диалога уже нет.
        await tester.tap(find.byIcon(Icons.auto_awesome));
        await tester.pumpAndSettle();
        expect(find.text(S.aiConsentText), findsNothing);
        expect(h.requests, hasLength(2));
      },
    );

    testWidgets('concern → статичный текст вместо чипов', (tester) async {
      final h = AiHarness(content: '{"steps": [], "concern": true}');
      await pumpField(tester, ai: h.ai);
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      expect(find.text(S.aiConcern), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('мусор вместо JSON → снекбар с ошибкой, поле пустое', (
      tester,
    ) async {
      final h = AiHarness(content: 'Вот шаги: открой файл');
      final controller = await pumpField(tester, ai: h.ai);
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      expect(find.text(S.aiError), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(controller.text, isEmpty);
    });
  });

  testWidgets(
    '«Проверить мысль»: ✨ заполняет «Как сказать точнее», паттерн и вопрос',
    (tester) async {
      final h = AiHarness(
        content:
            '{"pattern": "all_or_nothing", "question": "Что будет считаться достаточно хорошо?", "alternative": "Черновик — нормальный шаг.", "concern": false}',
      );
      final harness = await pumpScreen(
        tester,
        const Size(1280, 1200),
        RepositoryProvider.value(
          value: h.ai,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEpisodeSheet(
                context,
                source: EpisodeSource.manual,
                task: const PomoTask(
                  id: 'task',
                  description: 'Подключить webhook',
                  category: 'работа',
                  durationMinutes: 25,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        insightCubit: EpisodeInsight(order: [StrategyKind.thought]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.cause(Cause.perfect)));
      await tester.pumpAndSettle();
      // Без мысли подсказывать нечего.
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == S.fieldThought,
        ),
        'надо сразу идеально',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      final sent = jsonDecode(
        ((jsonDecode(h.requests.single.body) as Map)['messages']
                as List)[1]['content']
            as String,
      );
      expect(sent, {
        'thought': 'надо сразу идеально',
        'cause': 'perfect',
        'task': 'Подключить webhook',
      });
      expect(
        find.text(S.thinkingPattern(S.thinkingPatternName('all_or_nothing'))),
        findsOneWidget,
      );
      expect(
        find.text('Что будет считаться достаточно хорошо?'),
        findsOneWidget,
      );
      final alt = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == S.fieldAlt,
        ),
      );
      expect(alt.controller?.text, 'Черновик — нормальный шаг.');
      await harness.dispose();
    },
  );

  group('Разбор → ИИ', () {
    Sprint sprint({WeekReview? review}) => Sprint(
      id: '2026-W45',
      start: DateTime(2026, 11, 2),
      goal: 40,
      review: review,
    );

    testWidgets('без ключа кнопки нет, сохранённый разбор виден', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final h = AiHarness(enabled: false, content: '{}');
        final insight = _AiInsight(
          days: _days(),
          sprint: sprint(
            review: WeekReview(at: _now, summary: 'Старый разбор'),
          ),
        );
        final harness = await pumpScreen(
          tester,
          const Size(1280, 3200),
          RepositoryProvider.value(
            value: h.ai,
            child: const InsightScreen(showWindows: false),
          ),
          insightCubit: insight,
        );
        expect(find.text('Старый разбор'), findsOneWidget);
        expect(find.text(S.aiReview), findsNothing);
        expect(find.text(S.aiReviewRefresh), findsNothing);
        expect(h.requests, isEmpty);
        await harness.dispose();
      });
    });

    testWidgets('кнопка → разбор сохранён, эксперимент ИИ в предложении', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final h = AiHarness(
          content: jsonEncode({
            'summary': 'Старт стал раньше.',
            'patterns': [
              {'text': 'Непонятно с чего начать — 6 раз', 'evidence': '6 из 6'},
            ],
            'experiment': {
              'strategy': 'defuse',
              'metric': 'idle',
              'hypothesis': 'Если беру чувство с собой, то простой короче',
            },
            'concern': false,
          }),
        );
        final insight = _AiInsight(days: _days(), sprint: sprint());
        final harness = await pumpScreen(
          tester,
          const Size(1280, 3200),
          RepositoryProvider.value(
            value: h.ai,
            child: const InsightScreen(showWindows: false),
          ),
          insightCubit: insight,
        );
        expect(find.text(S.aiReviewRefresh), findsNothing);
        await tester.tap(find.text(S.aiReview));
        await tester.pumpAndSettle();
        expect(h.requests, hasLength(1));
        // В запрос не попали описания задач.
        expect(h.requests.single.body, isNot(contains('задача')));
        expect(insight.reviews.single.summary, 'Старт стал раньше.');
        expect(find.text('Старт стал раньше.'), findsOneWidget);
        expect(
          find.text('Если беру чувство с собой, то простой короче'),
          findsOneWidget,
        );
        expect(find.text(S.aiReviewRefresh), findsOneWidget);
        await harness.dispose();
      });
    });

    testWidgets('неизвестный способ — разбор есть, предложение по правилу', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final h = AiHarness(
          content: jsonEncode({
            'summary': 'Итог недели.',
            'experiment': {
              'strategy': 'meditate',
              'metric': 'idle',
              'hypothesis': 'Если медитирую, то начинаю раньше',
            },
          }),
        );
        final insight = _AiInsight(days: _days(), sprint: sprint());
        final harness = await pumpScreen(
          tester,
          const Size(1280, 3200),
          RepositoryProvider.value(
            value: h.ai,
            child: const InsightScreen(showWindows: false),
          ),
          insightCubit: insight,
        );
        await tester.tap(find.text(S.aiReview));
        await tester.pumpAndSettle();
        expect(find.text('Итог недели.'), findsOneWidget);
        expect(find.text('Если медитирую, то начинаю раньше'), findsNothing);
        expect(
          find.text(
            S.hypothesis(StrategyKind.firstStep, InsightMetric.firstStart),
          ),
          findsOneWidget,
        );
        await harness.dispose();
      });
    });
  });
}
