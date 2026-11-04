import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/widgets/day_card.dart';
import 'package:pomodoro_tracker/presentation/widgets/first_step_field.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

/// InsightCubit с готовыми днями: запись отметки не ходит в репозиторий,
/// а складывается в [checkIns] и сразу видна карточке.
class DayInsight extends InsightCubit {
  DayInsight([List<DayLog> days = const []])
    : super(FakeInsights(), FakeJournal(), FakeSprints(), episodeSettings) {
    emit(InsightState(status: InsightStatus.ready, days: days));
  }

  final checkIns = <CheckIn>[];

  @override
  Future<void> refresh() async {}

  void publish(List<DayLog> days) => emit(state.copyWith(days: days));

  @override
  Future<void> setCheckIn(CheckIn ck) async {
    checkIns.add(ck);
    final date = logicalDate(clock.now());
    final days = [...state.days];
    final i = days.indexWhere((d) => d.date == date);
    final day = i >= 0
        ? days[i]
        : DayLog(date: date, goal: 0, sessions: const []);
    final updated = day.copyWith(checkIn: day.checkIn.merge(ck));
    if (i >= 0) {
      days[i] = updated;
    } else {
      days.add(updated);
    }
    publish(days);
  }
}

DayLog _day(
  DateTime date, {
  CheckIn checkIn = const CheckIn(),
  List<Episode> episodes = const [],
}) => DayLog(
  date: date,
  goal: 0,
  sessions: const [],
  checkIn: checkIn,
  episodes: episodes,
);

Episode _episode(DateTime at, EpisodeSource source, {String id = 'e1'}) =>
    Episode(
      id: id,
      at: at,
      source: source,
      taskId: 'frog',
      task: 'Подключить Stripe',
    );

const _frog = PomoTask(
  id: 'frog',
  description: 'Подключить Stripe',
  category: 'работа',
  durationMinutes: 25,
  frog: true,
);

// 4 ноября 2026, среда. Вчера — 3 ноября.
final _today = DateTime(2026, 11, 4);
final _yesterday = DateTime(2026, 11, 3);

Future<ScreenHarness> _open(
  WidgetTester tester, {
  DayInsight? insight,
  List<PomoTask> todo = const [],
  Size size = const Size(1280, 900),
}) async {
  final tasks = EpisodeTasks()..seed(todo: todo);
  return pumpScreen(
    tester,
    size,
    const Align(alignment: Alignment.topCenter, child: DayCard()),
    tasksCubit: tasks,
    insightCubit: insight ?? DayInsight(),
  );
}

T _cubit<T>(WidgetTester tester) =>
    tester.element(find.byType(DayCard)).read<T>();

bool _empty(WidgetTester tester) =>
    tester.getSize(find.byType(DayCard)) == Size.zero;

Future<void> _tapDot(WidgetTester tester, String name, int n) async {
  await tester.tap(find.byKey(ValueKey('dots:$name:$n')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('утром без отметок — строка «Сон / Энергия», вечерней нет', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final h = await _open(tester);
      expect(find.text(S.sleepLabel), findsOneWidget);
      expect(find.text(S.energyLabel), findsOneWidget);
      expect(find.text(S.moodQuestion), findsNothing);
      // 5 кругов на строку, область нажатия не меньше 32 px.
      expect(find.byKey(ValueKey('dots:${S.sleepLabel}:5')), findsOneWidget);
      final size = tester.getSize(
        find.byKey(ValueKey('dots:${S.sleepLabel}:4')),
      );
      expect(size.width, greaterThanOrEqualTo(32));
      expect(size.height, greaterThanOrEqualTo(32));
      await h.dispose();
    });
  });

  testWidgets('тап по 4-й точке сна сохраняет setCheckIn(sleep: 4)', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final semantics = tester.ensureSemantics();
      final insight = DayInsight();
      final h = await _open(tester, insight: insight);
      await _tapDot(tester, S.sleepLabel, 4);
      expect(insight.checkIns, [const CheckIn(sleep: 4)]);
      // Сон отмечен, энергия — нет: строка остаётся, подпись точек читается.
      expect(find.text(S.energyLabel), findsOneWidget);
      expect(find.bySemanticsLabel(S.dotsLabel(S.sleepLabel, 4)), findsOne);
      await _tapDot(tester, S.energyLabel, 2);
      expect(insight.checkIns.last, const CheckIn(energy: 2));
      semantics.dispose();
      await h.dispose();
    });
  });

  testWidgets('сон и энергия отмечены — строки утра нет, карточки нет', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(_today, checkIn: const CheckIn(sleep: 4, energy: 3)),
      ]);
      final h = await _open(tester, insight: insight);
      expect(find.text(S.sleepLabel), findsNothing);
      expect(find.text(S.energyLabel), findsNothing);
      expect(_empty(tester), isTrue);
      await h.dispose();
    });
  });

  testWidgets('в 19:00 — вечерний вопрос, тап сохраняет настроение', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 19)), () async {
      final insight = DayInsight();
      final h = await _open(tester, insight: insight);
      expect(find.text(S.moodQuestion), findsOneWidget);
      expect(find.text(S.sleepLabel), findsNothing);
      await _tapDot(tester, S.moodQuestion, 5);
      expect(insight.checkIns, [const CheckIn(mood: 5)]);
      // Настроение отмечено — вопрос уходит.
      expect(find.text(S.moodQuestion), findsNothing);
      expect(_empty(tester), isTrue);
      await h.dispose();
    });
  });

  testWidgets('в 02:00 — ещё вечер логического дня', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 5, 2)), () async {
      // Логический день — 4 ноября: настроение за него ещё не отмечено.
      final h = await _open(tester);
      expect(find.text(S.moodQuestion), findsOneWidget);
      expect(find.text(S.sleepLabel), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('вчера не сдвинулась 🐸 — текст и обе кнопки', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(
          _yesterday,
          episodes: [
            _episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog),
          ],
        ),
      ]);
      final h = await _open(tester, insight: insight, todo: [_frog]);
      expect(find.text(S.yesterdayFrog), findsOneWidget);
      expect(find.text(S.whatGotInTheWay), findsOneWidget);
      expect(find.text(S.firstStepForFrog), findsOneWidget);

      // «Что помешало?» открывает лист эпизода.
      await tester.tap(find.text(S.whatGotInTheWay));
      await tester.pumpAndSettle();
      expect(find.text(S.episodeTitle), findsOneWidget);
      await h.dispose();
    });
  });

  testWidgets(
    '«Первый шаг для 🐸» открывает редактор с планом и пишет в задачу',
    (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
        final insight = DayInsight([
          _day(
            _yesterday,
            episodes: [
              _episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog),
            ],
          ),
        ]);
        final h = await _open(
          tester,
          insight: insight,
          todo: [
            const PomoTask(
              description: 'другая',
              category: 'работа',
              durationMinutes: 25,
              id: 'o',
            ),
            _frog,
          ],
        );
        await tester.tap(find.text(S.firstStepForFrog));
        await tester.pumpAndSettle();
        // «План старта» развёрнут сразу — поле шага видно.
        expect(find.byType(FirstStepField), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(FirstStepField),
            matching: find.byType(TextField),
          ),
          'открыть dashboard',
        );
        await tester.tap(find.text(S.save));
        await tester.pumpAndSettle();
        final frog = _cubit<TasksCubit>(
          tester,
        ).state.todo.firstWhere((t) => t.frog);
        expect(frog.firstStep, 'открыть dashboard');
        expect(frog.description, 'Подключить Stripe');
        await h.dispose();
      });
    },
  );

  testWidgets('без 🐸 сегодня кнопки «Первый шаг для 🐸» нет', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(
          _yesterday,
          episodes: [
            _episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog),
          ],
        ),
      ]);
      final h = await _open(tester, insight: insight);
      expect(find.text(S.yesterdayFrog), findsOneWidget);
      expect(find.text(S.whatGotInTheWay), findsOneWidget);
      expect(find.text(S.firstStepForFrog), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('два переноса вчера — строка со склонением, один — нет', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(
          _yesterday,
          checkIn: const CheckIn(sleep: 3, energy: 3),
          episodes: [
            _episode(DateTime(2026, 11, 3, 10), EpisodeSource.defer, id: 'a'),
          ],
        ),
      ]);
      final h = await _open(tester, insight: insight);
      expect(_empty(tester), isFalse); // утро сегодня не отмечено
      expect(find.textContaining('Вчера'), findsNothing);

      insight.publish([
        _day(
          _yesterday,
          episodes: [
            _episode(DateTime(2026, 11, 3, 10), EpisodeSource.defer, id: 'a'),
            _episode(DateTime(2026, 11, 3, 11), EpisodeSource.defer, id: 'b'),
          ],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(S.yesterdayDefers(2)), findsOneWidget);
      expect(S.yesterdayDefers(2), contains('2 переноса'));
      expect(S.yesterdayDefers(5), contains('5 переносов'));
      expect(S.yesterdayDefers(21), contains('21 перенос.'));
      await h.dispose();
    });
  });

  testWidgets('✕ скрывает «Вчера» и «План» до конца дня, завтра — снова', (
    tester,
  ) async {
    final frogWithCue = _frog.copyWith(cue: 'сяду после завтрака');
    final insight = DayInsight([
      _day(
        _yesterday,
        checkIn: const CheckIn(),
        episodes: [_episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog)],
      ),
    ]);
    late ScreenHarness h;
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      h = await _open(tester, insight: insight, todo: [frogWithCue]);
      expect(find.text(S.yesterdayFrog), findsOneWidget);
      expect(find.textContaining('сяду после завтрака'), findsOneWidget);

      await tester.tap(find.byTooltip(S.close));
      await tester.pumpAndSettle();
      expect(
        _cubit<SettingsCubit>(tester).state.settings.dayCardHidden,
        '2026-11-04',
      );
      expect(find.text(S.yesterdayFrog), findsNothing);
      expect(find.textContaining('сяду после завтрака'), findsNothing);
      // Самочувствие ✕ не трогает.
      expect(find.text(S.sleepLabel), findsOneWidget);
    });

    // Наступило 5 ноября: вчерашним стал день с 🐸 — логика снова по данным.
    await withClock(Clock.fixed(DateTime(2026, 11, 5, 9)), () async {
      insight.publish([
        _day(
          _today,
          episodes: [
            _episode(DateTime(2026, 11, 4, 23, 59), EpisodeSource.frog),
          ],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(S.yesterdayFrog), findsOneWidget);
      expect(find.textContaining('сяду после завтрака'), findsOneWidget);
      await h.dispose();
    });
  });

  testWidgets('план «если — то» 🐸: шаг, время; без 🐸 — верхняя задача', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 19)), () async {
      final insight = DayInsight([
        _day(_today, checkIn: const CheckIn(mood: 4)),
      ]);
      final withStep = _frog.copyWith(
        cue: 'сяду после завтрака',
        firstStep: 'открою api.dart',
        cueAt: '09:30',
      );
      final h = await _open(tester, insight: insight, todo: [withStep]);
      expect(
        find.text(
          S.planLine('сяду после завтрака', 'открою api.dart', '09:30'),
        ),
        findsOneWidget,
      );
      expect(
        S.planLine('сяду после завтрака', 'открою api.dart', '09:30'),
        '▸ Когда сяду после завтрака → открою api.dart · 09:30',
      );
      await h.dispose();
    });

    await withClock(Clock.fixed(DateTime(2026, 11, 4, 19)), () async {
      final insight = DayInsight([
        _day(_today, checkIn: const CheckIn(mood: 4)),
      ]);
      // 🐸 нет: берётся верхняя задача, шага нет — подставляется описание.
      final top = _frog.copyWith(frog: false, cue: 'открою ноут');
      final h = await _open(tester, insight: insight, todo: [top]);
      expect(
        find.text(S.planLine('открою ноут', 'Подключить Stripe', '')),
        findsOneWidget,
      );
      await h.dispose();
    });

    await withClock(Clock.fixed(DateTime(2026, 11, 4, 19)), () async {
      final insight = DayInsight([
        _day(_today, checkIn: const CheckIn(mood: 4)),
      ]);
      // Без cue плана нет, карточки тоже.
      final h = await _open(tester, insight: insight, todo: [_frog]);
      expect(_empty(tester), isTrue);
      await h.dispose();
    });
  });

  testWidgets('dayCard = false — карточки нет совсем', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(
          _yesterday,
          episodes: [
            _episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog),
          ],
        ),
      ]);
      final h = await _open(tester, insight: insight, todo: [_frog]);
      expect(find.text(S.sleepLabel), findsOneWidget);
      final settings = _cubit<SettingsCubit>(tester);
      await settings.update(settings.state.settings.copyWith(dayCard: false));
      await tester.pumpAndSettle();
      expect(_empty(tester), isTrue);
      expect(find.text(S.sleepLabel), findsNothing);
      expect(find.text(S.yesterdayFrog), findsNothing);
      await h.dispose();
    });
  });

  testWidgets('всё заполнено и закрыто — SizedBox.shrink без отступа', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 4, 9)), () async {
      final insight = DayInsight([
        _day(_today, checkIn: const CheckIn(sleep: 5, energy: 4)),
      ]);
      final h = await _open(tester, insight: insight, todo: [_frog]);
      expect(_empty(tester), isTrue);
      expect(
        find.descendant(
          of: find.byType(DayCard),
          matching: find.byType(Padding),
        ),
        findsNothing,
      );
      await h.dispose();
    });
  });

  for (final hour in [9, 19]) {
    testWidgets('на телефоне (320 px) в $hour:00 карточка не переполняется', (
      tester,
    ) async {
      await withClock(Clock.fixed(DateTime(2026, 11, 4, hour)), () async {
        final insight = DayInsight([
          _day(
            _yesterday,
            episodes: [
              _episode(DateTime(2026, 11, 3, 23, 59), EpisodeSource.frog),
            ],
          ),
        ]);
        final todo = [
          _frog.copyWith(
            cue: 'сяду после завтрака и открою рабочий ноутбук',
            firstStep: 'открою api.dart и найду место для вебхука',
            cueAt: '09:30',
          ),
        ];
        final h = await _open(
          tester,
          insight: insight,
          todo: todo,
          size: const Size(320, 800),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(S.whatGotInTheWay), findsOneWidget);
        await h.dispose();
      });
    });
  }

  test('dayCard и dayCardHidden: значения по умолчанию и круг через JSON', () {
    final old = AppSettings.fromJson(const {}, fallbackPath: '.');
    expect(old.dayCard, isTrue);
    expect(old.dayCardHidden, '');
    final copy = AppSettings.fromJson(
      old.copyWith(dayCard: false, dayCardHidden: '2026-11-04').toJson(),
      fallbackPath: '.',
    );
    expect(copy.dayCard, isFalse);
    expect(copy.dayCardHidden, '2026-11-04');
  });
}
