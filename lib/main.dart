import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import 'app/strings.dart';
import 'app/theme.dart';
import 'data/markdown_codec.dart' show dateKey, sprintId;
import 'data/timer_state_store.dart';
import 'data/vault_repositories.dart';
import 'domain/entities/app_settings.dart';
import 'domain/entities/pomo_session.dart' show logicalDate;
import 'presentation/cubits/journal_cubit.dart';
import 'presentation/cubits/settings_cubit.dart';
import 'presentation/cubits/sprint_cubit.dart';
import 'presentation/cubits/stats_cubit.dart';
import 'presentation/cubits/tasks_cubit.dart';
import 'presentation/cubits/timer_cubit.dart';
import 'presentation/home_shell.dart';
import 'services/notify_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    size: Size(1120, 800),
    minimumSize: Size(880, 620),
    title: S.appTitle,
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final sound = SoundService();
  await sound.init();
  final notify = NotifyService();
  await notify.init(S.appTitle);

  final settingsRepository = SettingsRepositoryImpl();
  final store = VaultStore(SettingsRepositoryImpl.defaultStoragePath());

  // Смена папки хранения: сначала перенаправить корень, затем перечитать
  // все данные — иначе старые данные из памяти перезапишут новый валт.
  Future<void> Function()? reloadVault;
  final settingsCubit = SettingsCubit(
    settingsRepository,
    initial: AppSettings.fromJson(const {}, fallbackPath: store.root),
    onStoragePathChanged: (path) {
      store.root = path;
      reloadVault?.call();
    },
  );
  await settingsCubit.load();
  AppSettings settings() => settingsCubit.state.settings;

  final taskRepository = TaskRepositoryImpl(store);
  final journalRepository = JournalRepositoryImpl(store);
  final sprintRepository = SprintRepositoryImpl(store);

  final tasksCubit = TasksCubit(
    taskRepository,
    journalRepository,
    settings,
    notify,
  );
  final statsCubit = StatsCubit(journalRepository, () => settings().dailyGoal);
  final sprintCubit = SprintCubit(
    sprintRepository,
    journalRepository,
    () => settings().sprintGoal,
    () => settings().dailyGoal,
    tasksCubit.weekTasks,
  );
  // Закрытая ⭐-задача недели уезжает в «Сделано за неделю» спринта.
  tasksCubit.onWeeklyClosed = sprintCubit.addDoneWeek;
  // Смена дня — сброс 🐸 (лягушка выбирается утром заново);
  // смена недели — сброс ⭐ (3 задачи спринта выбираются из вехи заново).
  Future<void> rolloverCheck() async {
    final today = dateKey(logicalDate(DateTime.now()));
    final week = sprintId(logicalDate(DateTime.now()));
    final current = settings();
    final newDay = current.lastDay != today;
    final newWeek = current.lastSprintId != week;
    if (!newDay && !newWeek) return;
    if (newDay) await tasksCubit.clearFrogs();
    if (newWeek) await tasksCubit.clearWeekFlags();
    // Из свежего стейта: за время await настройки могли измениться.
    await settingsCubit.update(
      settings().copyWith(lastDay: today, lastSprintId: week),
    );
  }

  final journalCubit = JournalCubit(
    journalRepository,
    settings,
    notify,
    onDayChanged: () async {
      await rolloverCheck();
      await statsCubit.refresh();
      await sprintCubit.refresh();
    },
  );
  final timerCubit = TimerCubit(
    settings: settings,
    sound: sound,
    notify: notify,
    store: TimerStateStore(),
    hasTodos: () => tasksCubit.hasTodos,
    onPomodoroComplete: (result) async {
      await tasksCubit.completeFromTimer(result);
      await journalCubit.refresh();
      await statsCubit.refresh();
      await sprintCubit.refresh();
    },
  );

  reloadVault = () async {
    await tasksCubit.load();
    await journalCubit.refresh();
    await statsCubit.refresh();
    await sprintCubit.refresh();
  };

  // Rollover — до refresh спринта, чтобы файл новой недели не создался
  // со звёздами прошлой.
  await tasksCubit.load();
  await rolloverCheck();
  await Future.wait([
    journalCubit.refresh(),
    statsCubit.refresh(),
    sprintCubit.refresh(),
  ]);
  await timerCubit.restore();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settingsCubit),
        BlocProvider.value(value: tasksCubit),
        BlocProvider.value(value: journalCubit),
        BlocProvider.value(value: statsCubit),
        BlocProvider.value(value: sprintCubit),
        BlocProvider.value(value: timerCubit),
      ],
      child: const PomodoroApp(),
    ),
  );
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key});

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp> {
  Timer? _autoTheme;

  @override
  void initState() {
    super.initState();
    // Тема «авто» зависит от времени суток — пересматриваем раз в минуту.
    _autoTheme = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          context.read<SettingsCubit>().state.settings.themeMode ==
              AppThemeMode.auto) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _autoTheme?.cancel();
    super.dispose();
  }

  /// Разрешаем тему сами (а не через `themeMode`/`darkTheme`), потому что
  /// matrix — не системная яркость, а отдельная палитра.
  ThemeData _theme(AppThemeMode mode) {
    final isSystemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    return switch (mode) {
      AppThemeMode.light => AppTheme.light(),
      AppThemeMode.dark => AppTheme.dark(),
      AppThemeMode.matrix => AppTheme.matrix(),
      AppThemeMode.system => isSystemDark ? AppTheme.dark() : AppTheme.light(),
      // Авто: светлая с 07:00 до 18:59, иначе тёмная (как в оригинале).
      AppThemeMode.auto =>
        DateTime.now().hour > 6 && DateTime.now().hour < 19
            ? AppTheme.light()
            : AppTheme.dark(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (prev, next) => prev.settings.scheme != next.settings.scheme,
      listener: (context, state) =>
          context.read<TimerCubit>().applySchemeIfIdle(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        buildWhen: (prev, next) =>
            prev.settings.themeMode != next.settings.themeMode ||
            prev.settings.language != next.settings.language,
        builder: (context, state) {
          S.lang = state.settings.language;
          return MaterialApp(
            title: S.appTitle,
            debugShowCheckedModeBanner: false,
            theme: _theme(state.settings.themeMode),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
