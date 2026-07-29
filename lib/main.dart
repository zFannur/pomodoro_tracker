import 'dart:async';
import 'dart:ffi' show nullptr;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'app/strings.dart';
import 'app/theme.dart';
import 'data/json_data_repository.dart';
import 'data/markdown_codec.dart' show dateKey, sprintId;
import 'data/timer_state_store.dart';
import 'data/vault_repositories.dart';
import 'domain/entities/app_settings.dart';
import 'domain/entities/pomo_session.dart' show logicalDate;
import 'presentation/cubits/journal_cubit.dart';
import 'presentation/cubits/settings_cubit.dart';
import 'presentation/cubits/sprint_cubit.dart';
import 'presentation/cubits/stats_cubit.dart';
import 'presentation/cubits/sync_cubit.dart';
import 'presentation/cubits/tasks_cubit.dart';
import 'presentation/cubits/timer_cubit.dart';
import 'presentation/home_shell.dart';
import 'services/drive_sync_service.dart';
import 'services/notify_service.dart';
import 'services/sound_service.dart';
import 'services/sync_auth.dart';

/// Один экземпляр на систему: два процесса держат список задач в памяти
/// и пишут tasks.json целиком — последний молча воскрешает удалённое.
/// Второй запуск поднимает окно первого и выходит.
void _ensureSingleInstance() {
  // OpenEvent, а не GetLastError после CreateEvent: Dart-рантайм делает
  // свои Win32-вызовы между FFI-вызовами и затирает код последней ошибки.
  final name = TEXT('pomodoro_tracker_single_instance');
  final existing = OpenEvent(EVENT_ALL_ACCESS, FALSE, name);
  if (existing == 0) {
    // Мы первые: создаём именованный event, живёт до конца процесса.
    CreateEvent(nullptr, TRUE, FALSE, name);
    return;
  }
  // ponytail: ищем по классу окна Flutter — заголовок меняется таймером;
  // если у пользователя окажется другое Flutter-окно, поднимем не то,
  // но данные в любом случае целы (процесс ниже выходит всегда).
  final hwnd = FindWindow(TEXT('FLUTTER_RUNNER_WIN32_WINDOW'), nullptr);
  if (hwnd != 0) {
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  }
  exit(0);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    _ensureSingleInstance();

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
  } else {
    // На мобильных нет USERPROFILE — корень хранилища в документах приложения.
    SettingsRepositoryImpl.mobileRoot =
        (await getApplicationDocumentsDirectory()).path;
  }

  final sound = SoundService();
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
  // Постоянный id устройства: по нему второе устройство отличает чужой
  // идущий помидор от своего и не пишет за него запись в журнал.
  if (settings().deviceId.isEmpty) {
    await settingsCubit.update(settings().copyWith(deviceId: newId()));
  }

  // Всё состояние живёт в data.json (AppData) и синхронизируется целиком;
  // валт получает markdown-зеркало и отдаёт захват через «Входящие.md».
  final dataRepository = JsonDataRepository(
    store,
    mirrorEnabled: () => settings().mirrorToVault,
  );
  final inbox = InboxImporter(store);

  final tasksCubit = TasksCubit(
    dataRepository,
    dataRepository,
    settings,
    notify,
  );
  final statsCubit = StatsCubit(dataRepository, () => settings().dailyGoal);
  final sprintCubit = SprintCubit(
    dataRepository,
    dataRepository,
    () => settings().sprintGoal,
    () => settings().dailyGoal,
    tasksCubit.weekTasks,
  );
  // Закрытая ⭐-задача недели уезжает в «Сделано за неделю» спринта.
  tasksCubit.onWeeklyClosed = sprintCubit.addDoneWeek;
  // Смена дня — сброс 🐸 (лягушка выбирается утром заново);
  // смена недели — сброс ⭐ (3 задачи спринта выбираются из вехи заново).
  Future<bool> rolloverCheck() async {
    final today = dateKey(logicalDate(DateTime.now()));
    final week = sprintId(logicalDate(DateTime.now()));
    // Отметки берём из синхронизируемого документа, а не из локальных
    // настроек: сброс должно делать ровно одно устройство, остальные узнают
    // о нём через слияние. Раньше телефон, открытый вечером, снимал ⭐,
    // расставленные утром на ПК, и отправлял это в Drive.
    final marks = (await dataRepository.rollover()).getOrElse(
      (_) => (day: null, week: null),
    );
    final newDay = marks.day != today;
    final newWeek = marks.week != week;
    if (!newDay && !newWeek) return false;
    if (newDay) await tasksCubit.clearFrogs();
    if (newWeek) await tasksCubit.clearWeekFlags();
    await dataRepository.markRollover(
      day: newDay ? today : null,
      week: newWeek ? week : null,
    );
    return true;
  }

  final journalCubit = JournalCubit(
    dataRepository,
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

  // Снимок таймера едет в data.json и обратно: идущий помидор виден
  // на втором устройстве, но завершает его только то, где он запущен.
  timerCubit.deviceId = () => settings().deviceId;
  timerCubit.onTransition = dataRepository.saveTimer;

  reloadVault = () async {
    await tasksCubit.load();
    await journalCubit.refresh();
    await statsCubit.refresh();
    await sprintCubit.refresh();
    timerCubit.adoptRemote(
      (await dataRepository.loadTimer()).getOrElse((_) => null),
    );
  };
  // Ручное «сделано» дописало запись в журнал — показать её сразу, иначе
  // задача уходит из «Сегодня», а в «Сделано» появляется только после
  // перезапуска.
  tasksCubit.onHistoryWritten = () async {
    await journalCubit.refresh();
    await statsCubit.refresh();
    await sprintCubit.refresh();
  };
  // Ручная правка журнала (удалили запись, поправили минуты) — статистика и
  // спринт иначе показывали старые цифры до перезапуска.
  journalCubit.onJournalChanged = () async {
    await statsCubit.refresh();
    await sprintCubit.refresh();
  };

  // Google Drive синк: data.json целиком — задачи, журнал, спринты.
  // Слияние по id с надгробиями, конфликт не теряет ни одной записи.
  final syncService = DriveSyncService(
    auth: SyncAuth(
      clientId: () => settings().syncClientId,
      clientSecret: () => settings().syncClientSecret,
      serverClientId: () => settings().syncServerClientId,
    ),
    localFile: dataRepository.jsonFile,
    // Записывает сам репозиторий: иначе документ в памяти разойдётся с
    // диском, и следующая правка похоронила бы всё, что только что приехало.
    applyRemote: dataRepository.applyRemote,
    onRemoteApplied: reloadVault,
  );
  final syncCubit = SyncCubit(syncService, settings);
  dataRepository.onSaved = syncCubit.scheduleSync;

  // Захват из «Входящие.md» (валт): при старте и при каждом фокусе окна.
  Future<void> drainInbox() async {
    for (final line in await inbox.drain()) {
      await tasksCubit.add(line, fallbackCategory: 'прочее', toPlanner: true);
    }
  }

  // Вернулись в приложение (фокус на Windows / resume на Android):
  // забрать инбокс и подтянуть удалённые правки.
  Future<void> onForeground() async {
    await drainInbox();
    await syncCubit.syncIfStale();
  }

  // Поднятие данных идёт ПОСЛЕ первого кадра: раньше здесь стояла цепочка
  // из миграции, обхода валта и трёх refresh — всё до runApp, и пользователь
  // смотрел на чёрный экран, пока она не отработает. Кубиты умеют показывать
  // status: loading, так что показывать есть что.
  Future<void> bootstrap() async {
    // Первый запуск синтезирует ~489 000 сэмплов — не на пути к первому кадру.
    await sound.init();
    // Сначала наполняем интерфейс локальными данными. Синк идёт ПОСЛЕ:
    // на Android он ждёт системный диалог входа, и всё это время журнал,
    // статистика и спринт стояли бы пустыми — приложение выглядело зависшим.
    await tasksCubit.load();
    await drainInbox();
    await Future.wait([
      journalCubit.refresh(),
      statsCubit.refresh(),
      sprintCubit.refresh(),
    ]);
    await timerCubit.restore();

    await syncCubit.init();
    // Rollover после синка: решать про смену дня и недели, не увидев правок
    // с другого устройства, значит стирать чужие свежие 🐸/⭐. Выполняется
    // после ПОПЫТКИ, а не после успеха — без сети сброс обязан работать.
    if (await rolloverCheck()) await sprintCubit.refresh();
  }

  unawaited(bootstrap());

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: settingsCubit),
        BlocProvider.value(value: tasksCubit),
        BlocProvider.value(value: journalCubit),
        BlocProvider.value(value: statsCubit),
        BlocProvider.value(value: sprintCubit),
        BlocProvider.value(value: timerCubit),
        BlocProvider.value(value: syncCubit),
      ],
      child: PomodoroApp(onWindowFocus: onForeground),
    ),
  );
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({this.onWindowFocus, super.key});

  /// Вернулись в окно — забрать захваченное из «Входящие.md».
  final Future<void> Function()? onWindowFocus;

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp>
    with WindowListener, WidgetsBindingObserver {
  Timer? _autoTheme;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
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
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _autoTheme?.cancel();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    widget.onWindowFocus?.call();
  }

  /// Android: вернулись в приложение. На Windows тем же занимается
  /// onWindowFocus — не дублируем.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !Platform.isWindows) {
      widget.onWindowFocus?.call();
    }
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
