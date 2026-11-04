import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

void main() {
  final date = DateTime(2026, 11, 4);
  final empty = DayLog(date: date, goal: 8, sessions: const []);
  final episode = Episode(
    id: 'e',
    at: DateTime(2026, 11, 4, 10, 15),
    source: EpisodeSource.idle,
    task: 'Stripe | webhook',
    cause: Cause.unclear,
    strategy: StrategyKind.firstStep,
    thought: 'надо | правильно',
  );
  final sprint = Sprint(id: '2026-W45', start: DateTime(2026, 11, 2), goal: 40);

  test('зеркало дня содержит русские секции и экранирует ячейки', () {
    final md = serializeDayLog(
      empty.copyWith(
        episodes: [episode],
        checkIn: const CheckIn(sleep: 4, energy: 3, mood: 4),
      ),
    );
    expect(md, contains('## Самочувствие\nСон 4 · Энергия 3 · День 4'));
    expect(md, contains('## Откладывания\n'));
    expect(
      md,
      contains('| Время | Сигнал | Задача | Причина | Способ | Мысль |'),
    );
    expect(
      md,
      contains(
        '| 10:15 | простой | Stripe ∣ webhook | '
        'непонятно, с чего начать | первый шаг | надо ∣ правильно |',
      ),
    );
  });

  test('без данных секций нет; частичная оценка без пустых подписей', () {
    final md = serializeDayLog(empty);
    expect(md, isNot(contains('## Самочувствие')));
    expect(md, isNot(contains('## Откладывания')));
    final partial = serializeDayLog(
      empty.copyWith(checkIn: const CheckIn(mood: 5)),
    );
    expect(partial, contains('## Самочувствие\nДень 5\n'));
    expect(partial, isNot(contains('Сон')));
    expect(partial, isNot(contains('Энергия')));
  });

  test('parseDayLog игнорирует новые секции и сохраняет сессии и заметки', () {
    final log = empty.copyWith(
      sessions: [
        PomoSession(
          id: 's',
          start: DateTime(2026, 11, 5, 0, 30),
          minutes: 25,
          category: 'код',
          task: 'задача | тест',
          frog: true,
        ),
      ],
      notes: const ['10:00 — заметка'],
    );
    final old = parseDayLog(serializeDayLog(log), date, 8);
    final md = serializeDayLog(
      log.copyWith(episodes: [episode], checkIn: const CheckIn(sleep: 4)),
    );
    final parsed = parseDayLog(md, date, 8);
    expect(parsed, old);
    expect(parsed.sessions, old.sessions);
    expect(parsed.notes, log.notes);
    expect(parsed.episodes, isEmpty);
  });

  test('parseDayLog не принимает похожую на сессию строку из новой секции', () {
    final md =
        '${serializeDayLog(empty)}\n## Откладывания\n'
        '| 10:00 | 25 | 0 | 0 | код | не сессия | таймер |\n';
    expect(parseDayLog(md, date, 8).sessions, isEmpty);
  });

  test('спринт: эксперимент и разбор с русскими подписями', () {
    final md = serializeSprint(
      sprint.copyWith(
        experiment: const Experiment(
          hypothesis: 'Шаг | помогает',
          strategy: StrategyKind.firstStep,
          metric: InsightMetric.firstStart,
          baseline: 48,
          verdict: Verdict.works,
        ),
        review: WeekReview(
          at: date,
          summary: 'Итог | недели',
          patterns: const [(text: 'Утро | лучше', evidence: '3 | дня')],
        ),
      ),
      const [],
    );
    expect(md, contains('## Эксперимент\n'));
    expect(md, contains('- Гипотеза: Шаг ∣ помогает'));
    expect(md, contains('- Способ: первый шаг'));
    expect(md, contains('- Метрика: первый помидор'));
    expect(md, contains('- Было: 48.0'));
    expect(md, contains('- Вердикт: работает'));
    expect(md, contains('## Разбор\nИтог ∣ недели'));
    expect(md, contains('- Утро ∣ лучше — 3 ∣ дня'));
    final parsed = parseSprint(md, sprint.id, sprint.start, 0);
    expect(parsed.goal, sprint.goal);
    expect(parsed.doneWeek, isEmpty);
  });

  test('спринт без данных не содержит новых секций, null не печатается', () {
    final md = serializeSprint(sprint, const []);
    expect(md, isNot(contains('## Эксперимент')));
    expect(md, isNot(contains('## Разбор')));
    final pending = serializeSprint(
      sprint.copyWith(
        experiment: const Experiment(
          hypothesis: 'тест',
          strategy: StrategyKind.rest,
          metric: InsightMetric.idle,
        ),
      ),
      const [],
    );
    expect(pending, contains('- Было: нет данных'));
    expect(pending, contains('- Вердикт: не подтверждён'));
    expect(pending, isNot(contains('null')));
  });

  test('все источники, причины, способы и метрики имеют русские подписи', () {
    final log = empty.copyWith(
      episodes: [
        for (final source in EpisodeSource.values)
          episode.copyWith(source: source),
        for (final cause in Cause.values) episode.copyWith(cause: cause),
        for (final strategy in StrategyKind.values)
          episode.copyWith(strategy: strategy),
        Episode(id: 'unknown', at: date, source: null),
      ],
    );
    final md = serializeDayLog(log);
    for (final label in [
      'простой',
      'стоп',
      'перенос',
      '🐸',
      'отвлечение',
      'вручную',
      'слишком большая',
      'скучно',
      'боюсь сделать плохо',
      'нет сил',
      'не вижу смысла',
      'отвлекли',
      'только 10 минут',
      'план «если — то»',
      'уменьшить задачу',
      'проверить мысль',
      'взять чувство с собой',
      'зачем это мне',
      'честный отдых',
      'убрать раздражитель',
    ]) {
      expect(md, contains(label));
    }
    for (final metric in InsightMetric.values) {
      final text = serializeSprint(
        sprint.copyWith(
          experiment: Experiment(
            hypothesis: 'тест',
            strategy: StrategyKind.rest,
            metric: metric,
          ),
        ),
        const [],
      );
      expect(text, isNot(contains(metric.name)));
    }
    for (final verdict in Verdict.values) {
      final text = serializeSprint(
        sprint.copyWith(
          experiment: Experiment(
            hypothesis: 'тест',
            strategy: StrategyKind.rest,
            metric: InsightMetric.idle,
            verdict: verdict,
          ),
        ),
        const [],
      );
      expect(text, isNot(contains(verdict.name)));
    }
  });
}
