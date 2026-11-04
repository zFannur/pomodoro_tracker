import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/app/help_content.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/home_shell.dart';
import 'package:pomodoro_tracker/presentation/screens/help_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/insight_screen.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

/// Курс, который можно менять на ходу.
class _Course extends FakeCourse {
  Course course = (directions: const <Direction>[], milestones: const <Milestone>[]);

  @override
  Future<Either<Failure, Course>> loadCourse() async => Either.right(course);
}

Course _readyCourse() => (
  directions: [
    for (final id in ['a', 'b'])
      Direction(id: id, name: id, categories: ['кат-$id']),
  ],
  milestones: [
    for (final id in ['a', 'b'])
      for (var i = 0; i < 3; i++)
        Milestone(id: '$id$i', directionId: id, title: 'веха $i', order: i),
  ],
);

const _wide = Size(1280, 900);
const _narrow = Size(400, 800);

/// Кнопка, открывающая справку; настоящий HomeShell тянет window_manager.
Widget _launcher({String? section, bool? windows}) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => showHelp(context, section: section, isWindows: windows),
      child: const Text('open'),
    ),
  ),
);

Future<ScreenHarness> _open(
  WidgetTester tester, {
  Size size = _wide,
  String? section,
  bool? windows,
}) async {
  final h = await pumpScreen(
    tester,
    size,
    _launcher(section: section, windows: windows),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Finder _menu(String id) => find.byKey(ValueKey('help-menu-$id'));

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('help-title'))).data!;

SettingsCubit _settings(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first).read<SettingsCubit>();

/// Есть ли в тексте фрагмент с фоном подсветки поиска (`tertiaryContainer`).
bool _highlighted(InlineSpan span, Color mark) {
  var found = false;
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor == mark && s.text != null) {
      found = true;
    }
    return !found;
  });
  return found;
}

void main() {
  setUp(() {
    S.lang = AppLanguage.ru;
    homeTab.value = 0;
    insightSubTab.value = 0;
  });
  tearDown(() => S.lang = AppLanguage.ru);

  group('широкий экран', () {
    testWidgets('строится без переполнения; меню — все разделы', (tester) async {
      final h = await _open(tester);
      expect(tester.takeException(), isNull);
      for (final s in helpSections()) {
        expect(_menu(s.id), findsOneWidget, reason: s.id);
      }
      // По умолчанию — «С чего начать» с путём внедрения.
      expect(_title(tester), '🚀 С чего начать');
      expect(find.byKey(const ValueKey('help-next-step')), findsOneWidget);
      expect(find.textContaining('Внедрение · этап 1 из 5'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('разделы листаются: далее, назад, меню', (tester) async {
      final h = await _open(tester);
      // Переходы — в конце раздела, до них надо дойти.
      await tester.ensureVisible(find.byKey(const ValueKey('help-next')));
      await tester.tap(find.byKey(const ValueKey('help-next')));
      await tester.pumpAndSettle();
      expect(_title(tester), '🧭 Как устроено');
      await tester.ensureVisible(find.byKey(const ValueKey('help-prev')));
      await tester.tap(find.byKey(const ValueKey('help-prev')));
      await tester.pumpAndSettle();
      expect(_title(tester), '🚀 С чего начать');
      await tester.tap(_menu('keys'));
      await tester.pumpAndSettle();
      expect(_title(tester), '⌨️ Клавиши и ввод');
      await h.dispose();
    });

    testWidgets('каждый раздел на русском и английском строится без ошибок', (
      tester,
    ) async {
      for (final lang in AppLanguage.values) {
        S.lang = lang;
        final h = await _open(tester);
        for (final s in helpSections()) {
          await tester.tap(_menu(s.id));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${lang.name} ${s.id}');
          expect(_title(tester), '${s.emoji} ${s.title}');
        }
        await h.dispose();
      }
    });

    testWidgets('поиск «разгон» оставляет разделы day, stuck и start', (
      tester,
    ) async {
      final h = await _open(tester);
      await tester.enterText(find.byType(TextField), 'разгон');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final id in ['start', 'day', 'stuck']) {
        expect(_menu(id), findsOneWidget, reason: id);
      }
      for (final s in helpSections()) {
        if (!['start', 'day', 'stuck'].contains(s.id)) {
          expect(_menu(s.id), findsNothing, reason: s.id);
        }
      }
      await h.dispose();
    });

    testWidgets('в найденном разделе совпадения подсвечены', (tester) async {
      final h = await _open(tester);
      await tester.enterText(find.byType(TextField), 'разгон');
      await tester.pumpAndSettle();
      await tester.tap(_menu('day'));
      await tester.pumpAndSettle();
      final mark = Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).colorScheme.tertiaryContainer;
      final lit = find.byWidgetPredicate(
        (w) => w is RichText && _highlighted(w.text, mark),
      );
      expect(lit, findsWidgets);
      // Без запроса подсветки нет.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(lit, findsNothing);
      await h.dispose();
    });

    testWidgets('пустой результат — «Ничего не нашлось»', (tester) async {
      final h = await _open(tester);
      await tester.enterText(find.byType(TextField), 'ъъъъъ');
      await tester.pumpAndSettle();
      expect(find.text(S.helpNothing), findsOneWidget);
      await h.dispose();
    });

    testWidgets('Esc закрывает справку', (tester) async {
      final h = await _open(tester);
      expect(find.byKey(const ValueKey('help-title')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-title')), findsNothing);
      await h.dispose();
    });

    testWidgets('крестик закрывает справку', (tester) async {
      final h = await _open(tester);
      await tester.tap(find.byTooltip(S.close).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-title')), findsNothing);
      await h.dispose();
    });
  });

  group('showHelp(section)', () {
    testWidgets('«ai» открывает нужный раздел (широкий)', (tester) async {
      final h = await _open(tester, section: 'ai');
      expect(_title(tester), '✨ ИИ-подсказки');
      await h.dispose();
    });

    testWidgets('«ai» открывает нужный раздел (узкий) и назад к списку', (
      tester,
    ) async {
      final h = await _open(tester, size: _narrow, section: 'ai');
      expect(find.text('✨ ИИ-подсказки'), findsOneWidget); // заголовок в AppBar
      expect(find.byKey(const ValueKey('help-title')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-card-ai')), findsOneWidget);
      await h.dispose();
    });

    testWidgets('английский язык: заголовки и поиск', (tester) async {
      S.lang = AppLanguage.en;
      final h = await _open(tester, section: 'ai');
      expect(_title(tester), '✨ AI hints');
      await tester.enterText(find.byType(TextField), 'warm-up');
      await tester.pumpAndSettle();
      expect(_menu('day'), findsOneWidget);
      expect(_menu('keys'), findsNothing);
      await h.dispose();
    });
  });

  group('узкий экран', () {
    testWidgets('список карточек строится без переполнения', (tester) async {
      final h = await _open(tester, size: _narrow);
      expect(tester.takeException(), isNull);
      // Первая карточка — прогресс пути.
      expect(find.textContaining('Внедрение · этап 1 из 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('help-card-levels')), findsOneWidget);
      await h.dispose();
    });

    testWidgets('тап по карточке открывает раздел; разделы без переполнения', (
      tester,
    ) async {
      final h = await _open(tester, size: _narrow);
      for (final id in ['start', 'levels', 'day', 'stuck', 'words', 'science']) {
        final card = find.byKey(ValueKey('help-card-$id'));
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await h.dispose();
    });

    testWidgets('поиск в списке фильтрует карточки', (tester) async {
      final h = await _open(tester, size: _narrow);
      await tester.enterText(find.byType(TextField), 'разгон');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-card-day')), findsOneWidget);
      expect(find.byKey(const ValueKey('help-card-keys')), findsNothing);
      await h.dispose();
    });

    testWidgets('Go закрывает справку целиком (список и раздел)', (
      tester,
    ) async {
      final h = await _open(tester, size: _narrow, section: 'levels');
      await tester.scrollUntilVisible(
        find.text('Открыть Курс'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Открыть Курс'));
      await tester.pumpAndSettle();
      expect(homeTab.value, 3);
      expect(find.byKey(const ValueKey('help-card-levels')), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await h.dispose();
    });
  });

  group('путь внедрения', () {
    testWidgets('ручная отметка пишет helpChecks и снимается', (tester) async {
      final h = await _open(tester);
      final cubit = _settings(tester);
      expect(cubit.state.settings.helpChecks, isEmpty);
      final box = find.byKey(const ValueKey('help-check-observe.nofix'));
      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(cubit.state.settings.helpChecks, ['observe.nofix']);
      expect(tester.widget<Checkbox>(box).value, isTrue);
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(cubit.state.settings.helpChecks, isEmpty);
      expect(tester.widget<Checkbox>(box).value, isFalse);
      await h.dispose();
    });

    testWidgets('«Следующий шаг» — первый невыполненный шаг этапа', (
      tester,
    ) async {
      final h = await _open(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('help-next-step')),
          matching: find.text('Следующий шаг: Заведи 2–3 направления — 0 из 2'),
        ),
        findsOneWidget,
      );
      await h.dispose();
    });

    testWidgets('кнопка «Открыть» на плашке ведёт к цели шага', (tester) async {
      final h = await _open(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('help-next-step')),
          matching: find.text(S.helpOpen),
        ),
      );
      await tester.pumpAndSettle();
      expect(homeTab.value, 3); // setup.dirs -> «Курс»
      expect(find.byKey(const ValueKey('help-title')), findsNothing);
      await h.dispose();
    });

    testWidgets('шаг «Windows» показывается только на Windows', (tester) async {
      var h = await _open(tester, windows: false);
      expect(find.byKey(const ValueKey('help-step-setup.distract')), findsNothing);
      expect(find.byKey(const ValueKey('help-step-setup.dirs')), findsOneWidget);
      await h.dispose();

      h = await _open(tester, windows: true);
      expect(
        find.byKey(const ValueKey('help-step-setup.distract')),
        findsOneWidget,
      );
      await h.dispose();
    });

    testWidgets('все шаги пути на месте; необязательные помечены', (
      tester,
    ) async {
      final h = await _open(tester, windows: true);
      for (final stage in adoptionStages()) {
        for (final step in stage.steps) {
          final finder = manualStepFinder(step.id);
          expect(finder, findsOneWidget, reason: step.id);
        }
      }
      expect(find.text(S.helpOptional), findsNWidgets(2)); // окна сессий и ИИ
      await h.dispose();
    });
  });

  group('автоотметки по данным', () {
    testWidgets('путь идёт за данными: этап 1 пройден — свёрнут, этап 2 текущий', (
      tester,
    ) async {
      final course = _Course();
      final directions = DirectionsCubit(course, FakeJournal());
      final h = await pumpScreen(
        tester,
        _wide,
        _launcher(windows: false),
        directionsCubit: directions,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Следующий шаг: Заведи 2–3 направления'), findsOneWidget);
      expect(find.byKey(const ValueKey('help-step-setup.dirs')), findsOneWidget);

      // Данные меняются при открытом окне — путь обновляется сам.
      course.course = _readyCourse();
      await directions.refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('Следующий шаг: Отмечай сон утром'), findsOneWidget);
      expect(find.textContaining('Внедрение · этап 2 из 5'), findsOneWidget);
      // Пройденный этап свёрнут; тап по заголовку раскрывает, шаги отмечены.
      expect(find.byKey(const ValueKey('help-step-setup.dirs')), findsNothing);
      await tester.tap(find.text('Настройка'));
      await tester.pumpAndSettle();
      final dirs = tester.widget<Icon>(
        find.byKey(const ValueKey('help-step-setup.dirs')),
      );
      expect(dirs.icon, Icons.check_circle);
      final ai = tester.widget<Icon>(find.byKey(const ValueKey('help-step-setup.ai')));
      expect(ai.icon, Icons.radio_button_unchecked);
      expect(tester.takeException(), isNull);
      await h.dispose();
      await directions.close();
    });

    testWidgets('нет кубитов в дереве — справка открывается без автоотметок', (
      tester,
    ) async {
      tester.view
        ..physicalSize = _wide
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _launcher())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Следующий шаг'), findsOneWidget);
      // Без SettingsCubit ручная отметка просто ничего не пишет.
      final box = find.byKey(const ValueKey('help-check-observe.nofix'));
      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(box).value, isFalse);
    });
  });

  group('подвкладки «Разбора»', () {
    testWidgets('insightSubTab переключает подвкладку и зеркалит выбор', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        _wide,
        const InsightScreen(showWindows: false),
        insightCubit: EpisodeInsight(),
      );
      int index() => DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      ).index;
      expect(index(), 0);
      expect(insightSubTab.value, 0);

      insightSubTab.value = 1;
      await tester.pumpAndSettle();
      expect(index(), 1);

      await tester.tap(find.text(S.insightTabWeek));
      await tester.pumpAndSettle();
      expect(index(), 0);
      expect(insightSubTab.value, 0);

      // Без трекера окон третьей подвкладки нет — индекс не применяется.
      insightSubTab.value = 2;
      await tester.pumpAndSettle();
      expect(index(), 0);
      expect(tester.takeException(), isNull);
      await h.dispose();
    });
  });

  group('кнопка Go', () {
    testWidgets('вкладка: меняет homeTab и закрывает справку', (tester) async {
      final h = await _open(tester, section: 'levels');
      await tester.ensureVisible(find.text('Открыть Курс'));
      await tester.tap(find.text('Открыть Курс'));
      await tester.pumpAndSettle();
      expect(homeTab.value, 3);
      expect(find.byKey(const ValueKey('help-title')), findsNothing);
      await h.dispose();
    });

    testWidgets('подвкладка «Окна»: insightSubTab и вкладка «Разбор»', (
      tester,
    ) async {
      final h = await _open(tester, section: 'windows');
      await tester.ensureVisible(find.text('Открыть окна'));
      await tester.tap(find.text('Открыть окна'));
      await tester.pumpAndSettle();
      expect(insightSubTab.value, 2);
      expect(homeTab.value, kInsightTab);
      await h.dispose();
    });

    testWidgets('«Разбор»: подвкладка «Неделя»', (tester) async {
      insightSubTab.value = 2;
      final h = await _open(tester, section: 'review');
      await tester.ensureVisible(find.text('Открыть Разбор'));
      await tester.tap(find.text('Открыть Разбор'));
      await tester.pumpAndSettle();
      expect(insightSubTab.value, 0);
      expect(homeTab.value, kInsightTab);
      await h.dispose();
    });
  });
}

/// Любой значок состояния шага: автошаг — иконка, ручной — флажок.
Finder manualStepFinder(String id) => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      (key.value == 'help-step-$id' || key.value == 'help-check-$id');
});
