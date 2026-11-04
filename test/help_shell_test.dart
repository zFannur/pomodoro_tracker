import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/home_shell.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

import 'episode_fakes.dart';
import 'screen_fakes.dart';

class _MemoryActivityStore extends ActivityStore {
  @override
  Future<ActivityData> load() async => ActivityData();

  @override
  Future<void> save(ActivityData data) async {}
}

const _title = ValueKey('help-title');

/// Настоящий HomeShell: первый запуск, F1 и кнопка «?» в навигации.
Future<void> _shell(
  WidgetTester tester,
  Future<void> Function(SettingsCubit settings) body, {
  Size size = const Size(1280, 900),
  AppSettings? settings,
}) async {
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
  final tracker = ActivityTracker(
    store: _MemoryActivityStore(),
    inPomodoro: () => false,
  );
  final activity = ActivityCubit(tracker);
  final h = await pumpScreen(
    tester,
    size,
    BlocProvider.value(value: activity, child: const HomeShell()),
    insightCubit: EpisodeInsight(),
    tasksCubit: EpisodeTasks()..seed(),
    timerCubit: EpisodeTimer(),
    appSettings: settings,
  );
  await tester.pumpAndSettle();
  await body(tester.element(find.byType(HomeShell)).read<SettingsCubit>());
  await h.dispose();
  await tester.runAsync(activity.close);
  await tester.runAsync(tracker.dispose);
}

void main() {
  setUp(() {
    S.lang = AppLanguage.ru;
    homeTab.value = 0;
  });

  testWidgets('первый запуск: справка открывается сама и запоминается', (
    tester,
  ) async {
    await _shell(
      tester,
      settings: AppSettings.fromJson(const {}, fallbackPath: '.'),
      (settings) async {
        expect(find.byKey(_title), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(_title)).data,
          '🚀 С чего начать',
        );
        expect(settings.state.settings.helpSeen, AppSettings.helpVersion);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('справка уже видена — сама не открывается', (tester) async {
    await _shell(tester, (settings) async {
      expect(find.byKey(_title), findsNothing);
    });
  });

  testWidgets('F1 открывает справку, второй F1 и Esc ничего не ломают', (
    tester,
  ) async {
    await _shell(tester, (settings) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsOneWidget);
      // Пока справка открыта, F1 не открывает вторую поверх.
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsNothing);
    });
  });

  testWidgets('F1 не срабатывает в поле ввода', (tester) async {
    await _shell(tester, (settings) async {
      homeTab.value = 1;
      await tester.pumpAndSettle();
      // Поле быстрого добавления; первый TextField на экране — выпадающий список.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == S.descriptionHint,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsNothing);
    });
  });

  testWidgets('иконка «?» в навигации открывает справку', (tester) async {
    await _shell(tester, (settings) async {
      await tester.tap(find.byTooltip(S.helpTooltip));
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsOneWidget);
    });
  });

  testWidgets('узкий экран: «?» в AppBar открывает список разделов', (
    tester,
  ) async {
    await _shell(size: const Size(400, 800), tester, (settings) async {
      await tester.tap(find.byTooltip(S.helpTooltip));
      await tester.pumpAndSettle();
      expect(find.byKey(_title), findsNothing);
      expect(find.byKey(const ValueKey('help-card-start')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
