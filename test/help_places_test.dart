import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/presentation/home_shell.dart';
import 'package:pomodoro_tracker/presentation/screens/course_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/help_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/insight_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/settings_dialog.dart';
import 'package:pomodoro_tracker/presentation/widgets/episode_sheet.dart';
import 'package:pomodoro_tracker/presentation/widgets/windows_dialog.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

class _MemoryActivityStore extends ActivityStore {
  @override
  Future<ActivityData> load() async => ActivityData();

  @override
  Future<void> save(ActivityData data) async {}
}

const _wide = Size(1280, 900);
const _title = ValueKey('help-title');

String _helpTitle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_title)).data!;

/// Кнопка, которая открывает [open]; чтобы проверить «?» внутри диалога.
Widget _launcher(void Function(BuildContext) open) => Builder(
  builder: (context) => Center(
    child: TextButton(onPressed: () => open(context), child: const Text('open')),
  ),
);

Future<void> _tapHelp(WidgetTester tester) async {
  await tester.tap(find.byTooltip(S.helpTitle));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    S.lang = AppLanguage.ru;
    homeTab.value = 0;
  });
  tearDown(() => S.lang = AppLanguage.ru);

  testWidgets('«Курс»: «?» ведёт в «Как устроено»', (tester) async {
    final h = await pumpScreen(tester, _wide, const CourseScreen());
    await _tapHelp(tester);
    expect(_helpTitle(tester), '🧭 Как устроено');
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('«Разбор → Неделя»: «?» ведёт в «Разбор и эксперименты»', (
    tester,
  ) async {
    final h = await pumpScreen(
      tester,
      _wide,
      const InsightScreen(showWindows: false),
      insightCubit: EpisodeInsight(),
    );
    await _tapHelp(tester);
    expect(_helpTitle(tester), '🔍 Разбор и эксперименты');
    await h.dispose();
  });

  testWidgets('лист эпизода: «?» ведёт в «Когда не идёт»', (tester) async {
    final h = await pumpScreen(
      tester,
      _wide,
      _launcher(
        (context) => showEpisodeSheet(context, source: EpisodeSource.manual),
      ),
      insightCubit: EpisodeInsight(),
      tasksCubit: EpisodeTasks()..seed(),
      timerCubit: EpisodeTimer(),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _tapHelp(tester);
    expect(_helpTitle(tester), '🧱 Когда не идёт');
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  for (final size in [_wide, const Size(400, 800)]) {
    testWidgets('диалог окон (${size.width.toInt()} px): «?» ведёт в «Окна»', (
      tester,
    ) async {
      final tracker = ActivityTracker(
        store: _MemoryActivityStore(),
        inPomodoro: () => false,
      );
      final activity = ActivityCubit(tracker);
      final h = await pumpScreen(
        tester,
        size,
        BlocProvider.value(
          value: activity,
          child: _launcher(
            (context) => showWindowsDialog(
              context,
              title: 'Задача',
              rows: () => const [],
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _tapHelp(tester);
      // На узком экране раздел открывается страницей с заголовком в AppBar.
      if (size.width < 900) {
        expect(find.text('🪟 Окна и отвлечения'), findsOneWidget);
      } else {
        expect(_helpTitle(tester), '🪟 Окна и отвлечения');
      }
      expect(tester.takeException(), isNull);
      await h.dispose();
      await tester.runAsync(activity.close);
      await tester.runAsync(tracker.dispose);
    });
  }

  group('настройки', () {
    testWidgets('initialTab открывает вкладку «ИИ»; «?» ведёт в «ИИ-подсказки»', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        _wide,
        _launcher(
          (context) => showSettingsDialog(context, initialTab: kSettingsTabAi),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(S.aiEnabledLabel), findsOneWidget);
      await _tapHelp(tester);
      expect(_helpTitle(tester), '✨ ИИ-подсказки');
      await h.dispose();
    });

    testWidgets('кнопка «Настройки ИИ» в справке открывает вкладку «ИИ»', (
      tester,
    ) async {
      final h = await pumpScreen(
        tester,
        _wide,
        _launcher((context) => showHelp(context, section: 'ai')),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Настройки ИИ'));
      await tester.tap(find.text('Настройки ИИ'));
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsNothing);
      expect(find.text(S.aiEnabledLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.dispose();
    });

    testWidgets('по умолчанию открывается «Таймер»', (tester) async {
      final h = await pumpScreen(
        tester,
        _wide,
        _launcher((context) => showSettingsDialog(context)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(S.pomodoroLen), findsOneWidget);
      expect(find.text(S.aiEnabledLabel), findsNothing);
      await h.dispose();
    });
  });
}
