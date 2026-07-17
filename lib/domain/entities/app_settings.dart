import 'package:equatable/equatable.dart';

/// Схема таймера: длительности в минутах.
class TimerScheme extends Equatable {
  const TimerScheme({
    required this.name,
    required this.pomodoro,
    required this.shortBreak,
    required this.longBreak,
    required this.longEvery,
  });

  factory TimerScheme.fromJson(Map<String, dynamic> json) {
    return TimerScheme(
      name: json['name'] as String? ?? 'classic',
      pomodoro: json['pomodoro'] as int? ?? 25,
      shortBreak: json['shortBreak'] as int? ?? 5,
      longBreak: json['longBreak'] as int? ?? 15,
      longEvery: json['longEvery'] as int? ?? 4,
    );
  }

  final String name;
  final int pomodoro;
  final int shortBreak;
  final int longBreak;

  /// Длинный перерыв через каждые N помидоров.
  final int longEvery;

  Map<String, dynamic> toJson() => {
    'name': name,
    'pomodoro': pomodoro,
    'shortBreak': shortBreak,
    'longBreak': longBreak,
    'longEvery': longEvery,
  };

  TimerScheme copyWith({
    String? name,
    int? pomodoro,
    int? shortBreak,
    int? longBreak,
    int? longEvery,
  }) {
    return TimerScheme(
      name: name ?? this.name,
      pomodoro: pomodoro ?? this.pomodoro,
      shortBreak: shortBreak ?? this.shortBreak,
      longBreak: longBreak ?? this.longBreak,
      longEvery: longEvery ?? this.longEvery,
    );
  }

  @override
  List<Object?> get props => [name, pomodoro, shortBreak, longBreak, longEvery];
}

/// Тема приложения. `auto` — светлая днём, тёмная ночью (как в оригинале).
/// `matrix` — чёрный фон, неоновый зелёный, моноширинный шрифт.
enum AppThemeMode { light, dark, system, auto, matrix }

/// Язык интерфейса.
enum AppLanguage { ru, en }

/// Финишный звук (набор как в оригинале).
enum FinishSound {
  bell,
  beep,
  chime,
  cuckoo,
  guitar,
  maramba,
  organ,
  rise,
  satellite,
  school,
}

/// Формат даты.
enum DateFmt {
  mdySlash('MM/DD/YYYY'),
  mdyDash('MM-DD-YYYY'),
  dmySlash('DD/MM/YYYY'),
  dmyDot('DD.MM.YYYY'),
  ymdDot('YYYY.MM.DD'),
  ymdDash('YYYY-MM-DD');

  const DateFmt(this.pattern);

  final String pattern;

  String format(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return switch (this) {
      DateFmt.mdySlash => '$mm/$dd/$yy',
      DateFmt.mdyDash => '$mm-$dd-$yy',
      DateFmt.dmySlash => '$dd/$mm/$yy',
      DateFmt.dmyDot => '$dd.$mm.$yy',
      DateFmt.ymdDot => '$yy.$mm.$dd',
      DateFmt.ymdDash => '$yy-$mm-$dd',
    };
  }
}

/// Формат времени: 24ч или 12ч.
enum TimeFmt { h24, h12 }

String formatClock(DateTime t, TimeFmt fmt) {
  final m = t.minute.toString().padLeft(2, '0');
  if (fmt == TimeFmt.h24) {
    return '${t.hour.toString().padLeft(2, '0')}:$m';
  }
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h12:$m${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Все настройки приложения.
class AppSettings extends Equatable {
  const AppSettings({
    required this.schemes,
    required this.activeScheme,
    required this.autostartPomodoro,
    required this.autostartBreak,
    required this.autostartIfTodo,
    required this.tasksTop,
    required this.completeRemove,
    this.flowtime = false,
    required this.dailyGoal,
    required this.volume,
    required this.finishSoundEnabled,
    required this.finishSound,
    required this.tickingSound,
    required this.tickingInBreaks,
    required this.notifications,
    required this.notifyMinuteBefore,
    required this.popupRaiseWindow,
    required this.msgPomodoroDone,
    required this.msgBreakDone,
    required this.telegramToken,
    required this.telegramChatId,
    required this.notifyTelegram,
    required this.themeMode,
    this.language = AppLanguage.ru,
    required this.dateFmt,
    required this.timeFmt,
    required this.storagePath,
    required this.categories,
    required this.sprintGoal,
    this.lastDay = '',
    this.lastSprintId = '',
    this.collapsedGroups = defaultCollapsedGroups,
  });

  factory AppSettings.fromJson(
    Map<String, dynamic> json, {
    required String fallbackPath,
  }) {
    final schemesRaw = json['schemes'] as List<dynamic>? ?? const [];
    final schemes = schemesRaw
        .whereType<Map<String, dynamic>>()
        .map(TimerScheme.fromJson)
        .toList();
    final categoriesRaw = json['categories'];
    // Категории: имя → привязанная схема (или null). Старый формат — список имён.
    final categories = <String, String?>{};
    if (categoriesRaw is Map<String, dynamic>) {
      for (final e in categoriesRaw.entries) {
        categories[e.key] = e.value is String ? e.value as String : null;
      }
    } else if (categoriesRaw is List) {
      for (final name in categoriesRaw.whereType<String>()) {
        categories[name] = null;
      }
    }
    return AppSettings(
      schemes: schemes.isEmpty ? defaultSchemes : schemes,
      activeScheme: json['activeScheme'] as String? ?? 'classic',
      autostartPomodoro: json['autostartPomodoro'] as bool? ?? false,
      autostartBreak: json['autostartBreak'] as bool? ?? true,
      autostartIfTodo: json['autostartIfTodo'] as bool? ?? false,
      tasksTop: json['tasksTop'] as bool? ?? true,
      completeRemove: json['completeRemove'] as bool? ?? true,
      flowtime: json['flowtime'] as bool? ?? false,
      dailyGoal: json['dailyGoal'] as int? ?? 8,
      volume: (json['volume'] as num? ?? 0.4).toDouble(),
      finishSoundEnabled: json['finishSoundEnabled'] as bool? ?? true,
      finishSound:
          FinishSound.values.asNameMap()[json['finishSound']] ??
          FinishSound.bell,
      tickingSound: json['tickingSound'] as bool? ?? false,
      tickingInBreaks: json['tickingInBreaks'] as bool? ?? false,
      notifications: json['notifications'] as bool? ?? true,
      notifyMinuteBefore: json['notifyMinuteBefore'] as bool? ?? false,
      popupRaiseWindow: json['popupRaiseWindow'] as bool? ?? false,
      msgPomodoroDone: json['msgPomodoroDone'] as String? ?? '',
      msgBreakDone: json['msgBreakDone'] as String? ?? '',
      telegramToken: json['telegramToken'] as String? ?? '',
      telegramChatId: json['telegramChatId'] as String? ?? '',
      notifyTelegram: json['notifyTelegram'] as bool? ?? false,
      themeMode:
          AppThemeMode.values.asNameMap()[json['themeMode']] ??
          AppThemeMode.system,
      language:
          AppLanguage.values.asNameMap()[json['language']] ?? AppLanguage.ru,
      dateFmt: DateFmt.values.asNameMap()[json['dateFmt']] ?? DateFmt.dmyDot,
      timeFmt: TimeFmt.values.asNameMap()[json['timeFmt']] ?? TimeFmt.h24,
      storagePath: json['storagePath'] as String? ?? fallbackPath,
      categories: categories.isEmpty
          ? {for (final c in defaultCategories) c: null}
          : categories,
      sprintGoal: json['sprintGoal'] as int? ?? 40,
      lastDay: json['lastDay'] as String? ?? '',
      lastSprintId: json['lastSprintId'] as String? ?? '',
      collapsedGroups:
          (json['collapsedGroups'] as List?)?.whereType<String>().toList() ??
          defaultCollapsedGroups,
    );
  }

  static const defaultSchemes = [
    TimerScheme(
      name: 'classic',
      pomodoro: 25,
      shortBreak: 5,
      longBreak: 15,
      longEvery: 4,
    ),
    TimerScheme(
      name: 'work',
      pomodoro: 50,
      shortBreak: 10,
      longBreak: 20,
      longEvery: 2,
    ),
    TimerScheme(
      name: 'personal',
      pomodoro: 30,
      shortBreak: 2,
      longBreak: 25,
      longEvery: 4,
    ),
  ];

  static const defaultCategories = ['работа', 'личное'];

  /// Свёрнутые по умолчанию группы экрана «Задачи».
  static const defaultCollapsedGroups = ['later', 'doneWeek'];

  final List<TimerScheme> schemes;
  final String activeScheme;

  /// Автостарт помидора после перерыва.
  final bool autostartPomodoro;

  /// Автостарт перерыва после помидора.
  final bool autostartBreak;

  /// Автостарт помидора только если есть задачи в плане.
  final bool autostartIfTodo;

  /// Новые задачи добавляются в начало списка.
  final bool tasksTop;

  /// Снимать задачу из плана при завершении помидора, даже если её
  /// остаток меньше длины помидора.
  final bool completeRemove;

  /// Flowtime: помидор дотикал — таймер тихо продолжает счёт вверх,
  /// пока не завершишь сам (помодоро для старта, поток не выбивается).
  final bool flowtime;

  /// Цель на день в помидорах; 0 — без цели.
  final int dailyGoal;

  /// Громкость 0..1.
  final double volume;
  final bool finishSoundEnabled;
  final FinishSound finishSound;
  final bool tickingSound;

  /// Тикать и во время перерывов.
  final bool tickingInBreaks;
  final bool notifications;
  final bool notifyMinuteBefore;

  /// Поднимать окно приложения, когда помидор/перерыв окончен
  /// (аналог «всплывающих окон» оригинала).
  final bool popupRaiseWindow;

  /// Кастомные тексты уведомлений: по строке на вариант, выбирается случайная.
  /// Пусто — стандартный текст.
  final String msgPomodoroDone;
  final String msgBreakDone;

  /// Telegram-уведомления через своего бота (локальный аналог оригинала).
  final String telegramToken;
  final String telegramChatId;
  final bool notifyTelegram;
  final AppThemeMode themeMode;
  final AppLanguage language;
  final DateFmt dateFmt;
  final TimeFmt timeFmt;

  /// Папка хранения markdown-файлов.
  final String storagePath;

  /// Категории: имя → имя привязанной схемы таймера (null — схема по умолчанию).
  final Map<String, String?> categories;

  /// Цель по умолчанию для нового спринта.
  final int sprintGoal;

  /// Служебное: последний увиденный логический день (сброс 🐸 по утрам).
  final String lastDay;

  /// Служебное: последняя увиденная неделя (сброс ⭐ в новый спринт).
  final String lastSprintId;

  /// Свёрнутые группы экрана «Задачи» (ключи групп).
  final List<String> collapsedGroups;

  TimerScheme get scheme => schemes.firstWhere(
    (s) => s.name == activeScheme,
    orElse: () => schemes.isEmpty ? defaultSchemes.first : schemes.first,
  );

  Map<String, dynamic> toJson() => {
    'schemes': schemes.map((s) => s.toJson()).toList(),
    'activeScheme': activeScheme,
    'autostartPomodoro': autostartPomodoro,
    'autostartBreak': autostartBreak,
    'autostartIfTodo': autostartIfTodo,
    'tasksTop': tasksTop,
    'completeRemove': completeRemove,
    'flowtime': flowtime,
    'dailyGoal': dailyGoal,
    'volume': volume,
    'finishSoundEnabled': finishSoundEnabled,
    'finishSound': finishSound.name,
    'tickingSound': tickingSound,
    'tickingInBreaks': tickingInBreaks,
    'notifications': notifications,
    'notifyMinuteBefore': notifyMinuteBefore,
    'popupRaiseWindow': popupRaiseWindow,
    'msgPomodoroDone': msgPomodoroDone,
    'msgBreakDone': msgBreakDone,
    'telegramToken': telegramToken,
    'telegramChatId': telegramChatId,
    'notifyTelegram': notifyTelegram,
    'themeMode': themeMode.name,
    'language': language.name,
    'dateFmt': dateFmt.name,
    'timeFmt': timeFmt.name,
    'storagePath': storagePath,
    'categories': categories,
    'sprintGoal': sprintGoal,
    'lastDay': lastDay,
    'lastSprintId': lastSprintId,
    'collapsedGroups': collapsedGroups,
  };

  AppSettings copyWith({
    List<TimerScheme>? schemes,
    String? activeScheme,
    bool? autostartPomodoro,
    bool? autostartBreak,
    bool? autostartIfTodo,
    bool? tasksTop,
    bool? completeRemove,
    bool? flowtime,
    int? dailyGoal,
    double? volume,
    bool? finishSoundEnabled,
    FinishSound? finishSound,
    bool? tickingSound,
    bool? tickingInBreaks,
    bool? notifications,
    bool? notifyMinuteBefore,
    bool? popupRaiseWindow,
    String? msgPomodoroDone,
    String? msgBreakDone,
    String? telegramToken,
    String? telegramChatId,
    bool? notifyTelegram,
    AppThemeMode? themeMode,
    AppLanguage? language,
    DateFmt? dateFmt,
    TimeFmt? timeFmt,
    String? storagePath,
    Map<String, String?>? categories,
    int? sprintGoal,
    String? lastDay,
    String? lastSprintId,
    List<String>? collapsedGroups,
  }) {
    return AppSettings(
      schemes: schemes ?? this.schemes,
      activeScheme: activeScheme ?? this.activeScheme,
      autostartPomodoro: autostartPomodoro ?? this.autostartPomodoro,
      autostartBreak: autostartBreak ?? this.autostartBreak,
      autostartIfTodo: autostartIfTodo ?? this.autostartIfTodo,
      tasksTop: tasksTop ?? this.tasksTop,
      completeRemove: completeRemove ?? this.completeRemove,
      flowtime: flowtime ?? this.flowtime,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      volume: volume ?? this.volume,
      finishSoundEnabled: finishSoundEnabled ?? this.finishSoundEnabled,
      finishSound: finishSound ?? this.finishSound,
      tickingSound: tickingSound ?? this.tickingSound,
      tickingInBreaks: tickingInBreaks ?? this.tickingInBreaks,
      notifications: notifications ?? this.notifications,
      notifyMinuteBefore: notifyMinuteBefore ?? this.notifyMinuteBefore,
      popupRaiseWindow: popupRaiseWindow ?? this.popupRaiseWindow,
      msgPomodoroDone: msgPomodoroDone ?? this.msgPomodoroDone,
      msgBreakDone: msgBreakDone ?? this.msgBreakDone,
      telegramToken: telegramToken ?? this.telegramToken,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      notifyTelegram: notifyTelegram ?? this.notifyTelegram,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      dateFmt: dateFmt ?? this.dateFmt,
      timeFmt: timeFmt ?? this.timeFmt,
      storagePath: storagePath ?? this.storagePath,
      categories: categories ?? this.categories,
      sprintGoal: sprintGoal ?? this.sprintGoal,
      lastDay: lastDay ?? this.lastDay,
      lastSprintId: lastSprintId ?? this.lastSprintId,
      collapsedGroups: collapsedGroups ?? this.collapsedGroups,
    );
  }

  /// Схема для категории: привязанная или активная.
  TimerScheme schemeFor(String category) {
    final bound = categories[category];
    if (bound == null) return scheme;
    return schemes.firstWhere((s) => s.name == bound, orElse: () => scheme);
  }

  @override
  List<Object?> get props => [
    schemes,
    activeScheme,
    autostartPomodoro,
    autostartBreak,
    autostartIfTodo,
    tasksTop,
    completeRemove,
    flowtime,
    dailyGoal,
    volume,
    finishSoundEnabled,
    finishSound,
    tickingSound,
    tickingInBreaks,
    notifications,
    notifyMinuteBefore,
    popupRaiseWindow,
    msgPomodoroDone,
    msgBreakDone,
    telegramToken,
    telegramChatId,
    notifyTelegram,
    themeMode,
    language,
    dateFmt,
    timeFmt,
    storagePath,
    categories,
    sprintGoal,
    lastDay,
    lastSprintId,
    collapsedGroups,
  ];
}
