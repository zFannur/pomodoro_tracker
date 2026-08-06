import '../domain/entities/app_settings.dart';

/// Все строки интерфейса, на двух языках — переключаются в настройках
/// ([S.lang]) и меняют текст немедленно (виджеты читают геттеры при
/// каждой перестройке, поэтому строки не помечены `const`).
abstract final class S {
  static AppLanguage lang = AppLanguage.ru;

  static String _t(String ru, String en) => lang == AppLanguage.ru ? ru : en;

  static String get appTitle => _t('Помодоро Трекер', 'Pomodoro Tracker');

  // Навигация
  static String get navTimer => _t('Таймер', 'Timer');
  static String get navTasks => _t('Задачи', 'Tasks');
  static String get navSprint => _t('Спринт', 'Sprint');
  static String get navStats => _t('Статистика', 'Stats');

  // Таймер
  static String get pomodoroWord => _t('ПОМИДОР', 'POMODORO');
  static String get takeShortBreak =>
      _t('Пора сделать короткий перерыв.', 'Time for a short break.');
  static String get takeLongBreak =>
      _t('Пора сделать длинный перерыв.', 'Time for a long break.');
  static String get shortBreakTitle => _t('КОРОТКИЙ ПЕРЕРЫВ', 'SHORT BREAK');
  static String get longBreakTitle => _t('ДЛИННЫЙ ПЕРЕРЫВ', 'LONG BREAK');
  static String get breakWord => _t('перерыв', 'break');

  static String get onOtherDevice =>
      _t('идёт на другом устройстве', 'running on another device');
  static String get series => _t('серия', 'series');
  static String get start => _t('Старт', 'Start');
  static String get stop => _t('Стоп', 'Stop');
  static String get pause => _t('Пауза', 'Pause');
  static String get resume => _t('Продолжить', 'Resume');
  static String get doneEarly => _t('Готово', 'Done');
  static String get skip => _t('Пропустить', 'Skip');
  static String get delayLabel => _t('ЗАДЕРЖКА', 'DELAY');
  static String get prolong => _t('+1 мин (Shift — +5)', '+1 min (Shift — +5)');
  static String get forwardHint => _t('Прокрутить фазу', 'Skip forward');
  static String get fullscreen => _t('Полный экран', 'Fullscreen');
  static String get hintKeys => _t(
    'Space — старт/пауза · Esc Esc — стоп/пропуск · +/− — помидоры первой задачи (Shift — ×4)',
    'Space — start/pause · Esc Esc — stop/skip · +/− — pomodoros of the first task (Shift — ×4)',
  );

  // Задачи
  static String get planned => _t('Запланировано', 'Planned');
  static String get categoryHint => _t('Категория', 'Category');
  static String get descriptionHint =>
      _t('#категория описание ~помидоры', '#category description ~pomodoros');
  static String get add => _t('Добавить', 'Add');
  static String get planner => _t('Планировщик', 'Planner');
  static String get emptyPlanned => _t('Список планирования пуст.', 'The plan is empty.');
  static String get emptyPlannedHint =>
      _t('Добавьте задачи через форму выше.', 'Add tasks using the form above.');
  static String get finishTime => _t('ВРЕМЯ ОКОНЧАНИЯ', 'FINISH TIME');
  static String get nextLongBreak => _t('Следующий длинный перерыв', 'Next long break');
  static String get categories => _t('Категории', 'Categories');
  static String get hintTasks => _t(
    'Клик — редактирование. Клик по числу — +помидор (Alt — минус, Shift — ×4). Перетаскивайте для сортировки.',
    'Click — edit. Click the number — +pomodoro (Alt — minus, Shift — ×4). Drag to reorder.',
  );
  static String get menuAddPomo => _t('Добавить помидор', 'Add a pomodoro');
  static String get menuRemovePomo => _t('Убрать один', 'Remove one');
  static String get menuMarkDone => _t('Отметить как выполненное', 'Mark as done');
  static String get menuCloseWhole => _t('Закрыть задачу целиком', 'Close the whole task');
  static String get menuSplit => _t('Разбить', 'Split');
  static String get menuMerge => _t('Объединить', 'Merge');
  static String get menuToInbox => _t('Во входящие', 'To inbox');
  static String get menuToTomorrow => _t('Перенести на завтра', 'Move to tomorrow');
  static String get menuToLater => _t('Перенести на позже', 'Move to later');
  static String get delete => _t('Удалить', 'Delete');
  static String get close => _t('Закрыть', 'Close');
  static String get cancel => _t('Отмена', 'Cancel');
  static String get editTask => _t('Редактировать задачу', 'Edit task');
  static String get confirmClear => _t(
    'Очистить «Сегодня»? Задачи уедут в корзину — их можно будет вернуть.',
    'Clear "Today"? Tasks go to Trash — you can bring them back.',
  );
  static String get withoutNote => _t('Без заметки', 'No note');
  static String get emptyBucket => _t('Пусто', 'Empty');
  static String get listSettings => _t('Настроить', 'Configure');
  static String get tasksTopLabel => _t('Новые задачи — наверх', 'New tasks go to the top');
  static String get completeRemoveLabel => _t(
    'Снимать задачу при завершении помидора',
    'Remove task when a pomodoro finishes it',
  );
  static String get clearList => _t('Очистить список', 'Clear list');
  static String get toToday => _t('В «Сегодня»', 'To "Today"');
  static String get save => _t('Сохранить', 'Save');

  // Сделано
  static String get doneTitle => _t('Сделано', 'Done');
  static String get focusLabel => _t('фокус', 'focus');
  static String get delaysLabel => _t('задержки', 'delays');
  static String get interruptionsLabel => _t('прерывания', 'interruptions');
  static String get manualMark => _t('вручную', 'manual');
  static String get goalLine => _t('Цель дня', 'Daily goal');
  static String get goalLeft => _t('осталось', 'left');
  static String get menuRepeat => _t('Повторить', 'Repeat');
  static String get menuFillBlanks => _t('Заполнить пустые', 'Fill the gaps');
  static String get emptyDone => _t('Сегодня ещё нет помидоров.', 'No pomodoros yet today.');
  static String get todoEmptyDone =>
      _t('Отличная работа! Список задач пуст.', 'Great work! The task list is empty.');
  static String get goalCompleted =>
      _t('Поздравляем! Дневная цель выполнена.', 'Congrats! Daily goal reached.');
  static String get dayCleared => _t(
    'Новый день — список «Сделано» начат заново.',
    'New day — the "Done" list starts over.',
  );

  // Планировщик (корзины — это СРОКИ, не спринт)
  static String get dueNow => _t('Пора', 'Due');
  static String get inbox => _t('Входящие', 'Inbox');
  static String get tomorrow => _t('Завтра', 'Tomorrow');
  static String get week => _t('Эта неделя', 'This week');
  static String get later => _t('Позже', 'Later');

  // Неделя (спринт)
  static String get sprintGoal => _t('Цель недели (🍅)', 'Weekly goal (🍅)');
  static String get sprintFact => _t('Факт', 'Actual');
  static String get sprintByDay => _t('По дням', 'By day');
  static String get sprintHistory => _t('Прошлые недели', 'Past weeks');
  static String get sprintVelocity => _t('Темп', 'Velocity');
  static String get perDay => _t('🍅/день', '🍅/day');
  static String get forecast => _t('Прогноз', 'Forecast');
  static String get milestone => _t('Веха недели', 'Weekly milestone');
  static String get milestoneHint => _t(
    'Тонкий срез до реальности, проверяется бинарно: «товар покупается живым юзером»',
    'A thin slice of reality, checked as pass/fail: "a real user buys the product"',
  );
  static String get weekTasksTitle => _t('Задачи спринта (⭐)', 'Sprint tasks (⭐)');
  static String get weekTasksEmpty => _t(
    'Отметь 2–3 задачи звездой в Планировщике (кнопка «Выбрать») — они двигают веху. '
        'В новую неделю звёзды снимаются автоматически.',
    'Star 2–3 tasks in the Planner (the "Pick" button) — they move the milestone. '
        'Stars are cleared automatically at the start of a new week.',
  );
  static String get pickWeekTasks => _t('Выбрать', 'Pick');
  static String get plannerHint => _t(
    '🐸 и ⭐ ставятся здесь. Корзины (Завтра/Эта неделя/Позже) — это сроки; '
        'спринт — только ⭐: 3 задачи из текущей вехи.',
    '🐸 and ⭐ are set here. Buckets (Tomorrow/This week/Later) are due dates; '
        'the sprint is only ⭐: 3 tasks from the current milestone.',
  );
  static String get doneWeekTitle => _t('Сделано за неделю', 'Done this week');

  static String get doneWeekEmpty => _t(
    'Пока пусто — здесь появится всё, что закроешь на этой неделе.',
    'Empty so far — everything you close this week shows up here.',
  );
  static String get doneTodayTitle => _t('Сделано сегодня', 'Done today');
  static String get doneTodayEmpty =>
      _t('Сегодня пока ничего не закрыто', 'Nothing closed today yet');
  static String get noDescription => _t('без описания', 'no description');
  static String get minShort => _t('мин', 'min');

  // Система фокуса
  static String get nowLabel => _t('СЕЙЧАС', 'NOW');
  static String get nowEmpty =>
      _t('Возьми одну задачу — верхняя в списке и есть СЕЙЧАС', 'Pick one task — the top of the list is NOW');
  static String get frogLabel => _t('🐸 Лягушка дня — делается первой', '🐸 Frog of the day — do it first');
  static String get frogRemove => _t('Убрать лягушку', 'Remove the frog');
  static String get weekMark => _t(
    '⭐ В спринт — двигает веху недели (снимается в новую неделю)',
    '⭐ To the sprint — moves the weekly milestone (cleared next week)',
  );
  static String get weekUnmark => _t('Убрать из спринта', 'Remove from sprint');
  static String get toInbox => _t('Сразу во «Входящие»', 'Straight to "Inbox"');
  static String get dayOverload => _t(
    'По системе: 🐸 + 2 задачи на день. Лишнее — во «Входящие» (меню ⋮).',
    'The system: 🐸 + 2 tasks a day. Extra goes to "Inbox" (⋮ menu).',
  );
  static String get stuckHint =>
      _t('Застрял? Разбей до шага на 5 минут — и стартуй.', "Stuck? Break it down to a 5-minute step — and start.");
  static String get whereStopped => _t('На чём встал?', 'Where did you leave off?');
  static String get whereStoppedHint => _t(
    'Одна строка — чтобы завтра не вспоминать (можно пропустить)',
    "One line, so you don't have to remember tomorrow (optional)",
  );
  static String get notesTitle => _t('Заметки', 'Notes');
  static String get overtime => _t('поток', 'flow');

  // Статистика
  static String get periodToday => _t('Сегодня', 'Today');
  static String get periodWeek => _t('Неделя', 'Week');
  static String get periodMonth => _t('Месяц', 'Month');
  static String get periodYear => _t('365 дней', '365 days');
  static String get periodCustom => _t('Диапазон', 'Range');
  static String get statPomodoros => _t('Помидоры', 'Pomodoros');
  static String get statFocus => _t('Фокус', 'Focus');
  static String get statTime => _t('Время', 'Time');
  static String get statStreak => _t('Серия дней', 'Day streak');
  static String get statBestDay => _t('Лучший день', 'Best day');
  static String get statFrog => _t('🐸 Лягушки', '🐸 Frogs');
  static String get statFrogHint => _t('дней, где сделал главное', "days you got the main thing done");
  static String get statByCategory => _t('По категориям', 'By category');
  static String get statLast14 => _t('Последние 14 дней', 'Last 14 days');
  static String get statHeatmap => _t('Карта активности', 'Activity map');
  static String get statEmpty => _t('Пока нет ни одного помидора за период.', 'No pomodoros in this period yet.');
  static String get daysSuffix => _t('дн.', 'd.');

  // Настройки
  static String get settings => _t('Настройки', 'Settings');
  static String get tabTimer => _t('Таймер', 'Timer');
  static String get tabNotify => _t('Оповещения', 'Notifications');
  static String get tabApp => _t('Приложение', 'App');
  static String get settingsSchemes => _t('Схемы', 'Schemes');
  static String get schemeName => _t('Название схемы', 'Scheme name');
  static String get pomodoroLen => _t('Продолжительность помидора, мин', 'Pomodoro length, min');
  static String get shortLen => _t('Короткий перерыв, мин', 'Short break, min');
  static String get longLen => _t('Длинный перерыв, мин', 'Long break, min');
  static String get longEvery => _t('Длинный перерыв через каждые N помидоров', 'Long break every N pomodoros');
  static String get autostartPomodoro => _t('Автостарт помидора после перерыва', 'Auto-start pomodoro after a break');
  static String get autostartBreak => _t('Автостарт перерыва после помидора', 'Auto-start break after a pomodoro');
  static String get autostartIfTodo => _t(
    'Автостарт помидора только при наличии задач',
    'Auto-start pomodoro only if tasks are queued',
  );
  static String get flowtimeLabel => _t(
    'Flowtime: не выбивать из потока (помидор дотикал — таймер тихо считает дальше)',
    "Flowtime: don't break the flow (pomodoro ends — the timer quietly keeps counting)",
  );
  static String get dailyGoal => _t('Цель на день, 🍅 (0 — без цели)', 'Daily goal, 🍅 (0 — no goal)');
  static String get volume => _t('Громкость', 'Volume');
  static String get finishSound => _t('Финишный звук', 'Finish sound');
  static String get finishMelody => _t('Мелодия финиша', 'Finish melody');
  static String get tickingSound => _t('Тикающий звук во время помидора', 'Ticking sound during a pomodoro');
  static String get tickingInBreaks => _t('Тикать и в перерывах', 'Tick during breaks too');
  static String get notifications => _t('Системные уведомления', 'System notifications');
  static String get notifyMinuteBefore => _t('Предупреждать за минуту до конца', 'Warn one minute before the end');
  static String get popupRaiseWindow => _t('Поднимать окно, когда фаза окончена', 'Raise the window when a phase ends');
  static String get messages => _t('Сообщения', 'Messages');
  static String get msgPomodoroHint => _t(
    'Тексты для «Помидор завершён» — по одному на строку, выбирается случайный',
    'Texts for "Pomodoro finished" — one per line, a random one is picked',
  );
  static String get msgBreakHint => _t('Тексты для «Перерыв окончен»', 'Texts for "Break finished"');
  static String get telegram => _t('Telegram', 'Telegram');
  static String get telegramToken => _t('Токен бота', 'Bot token');
  static String get telegramChatId => _t('Chat ID', 'Chat ID');
  static String get notifyTelegram => _t('Дублировать уведомления в Telegram', 'Duplicate notifications to Telegram');
  static String get sendTest => _t('Отправить тестовое оповещение', 'Send a test notification');
  static String get testNotification => _t('Проверка уведомлений', 'Notification test');
  static String get themeMode => _t('Цветовая схема', 'Color theme');
  static String get themeLight => _t('Светлая', 'Light');
  static String get themeDark => _t('Тёмная', 'Dark');
  static String get themeSystem => _t('Системная', 'System');
  static String get themeAuto => _t('Авто', 'Auto');
  static String get themeMatrix => _t('Матрица', 'Matrix');
  static String get language => _t('Язык', 'Language');
  static String get languageRu => 'Русский';
  static String get languageEn => 'English';
  static String get dateFormat => _t('Формат даты', 'Date format');
  static String get timeFormat => _t('Формат времени', 'Time format');
  static String get storageFolder => _t('Папка хранения (markdown)', 'Storage folder (markdown)');
  static String get mirrorToVaultLabel => _t(
    'Зеркалить задачи в валт («Задачи.md», только просмотр)',
    'Mirror tasks to the vault ("Задачи.md", view-only)',
  );
  static String get chooseFolder => _t('Выбрать…', 'Choose…');
  static String get newCategory => _t('Новая категория', 'New category');
  static String get boundScheme => _t('Схема категории', 'Category scheme');
  static String get defaultScheme => _t('по умолчанию', 'default');
  static String get sprintGoalDefault => _t('Цель спринта по умолчанию, 🍅', 'Default sprint goal, 🍅');
  static String get addScheme => _t('Добавить схему', 'Add scheme');
  static String get notifyMinuteLeft => _t('Осталась минута', 'One minute left');
  static String get notifyPomodoroDone => _t('Помидор завершён!', 'Pomodoro finished!');
  static String get notifyBreakDone => _t('Перерыв окончен', 'Break finished');
  static String get notifyBreakDoneBody => _t('Следующий помидор будет лучше!', 'The next pomodoro will be better!');

  // Таблица истории спринтов, поле минут в диалоге редактирования записи
  static String get sprintWord => _t('Спринт', 'Sprint');
  static String get colWeek => _t('Неделя', 'Week');
  static String get colGoal => _t('Цель', 'Goal');
  static String get minutesField => _t('Минуты', 'Minutes');
  static String pomoClickHint(int minutes) => _t(
    '$minutesм · клик +1 🍅, Alt-клик −1, Shift ×4',
    '${minutes}m · click +1 🍅, Alt-click −1, Shift ×4',
  );

  // Экран задач
  static String get quickAddHint => _t(
    'Enter — во «Входящие» · Ctrl+Enter — в «Сегодня» · Ctrl+N — сюда из любого места',
    'Enter — to "Inbox" · Ctrl+Enter — to "Today" · Ctrl+N — jump here from anywhere',
  );
  static String get undo => _t('Отменить', 'Undo');
  static String get taskDeleted => _t('Задача удалена', 'Task deleted');
  static String get trashTitle => _t('Корзина', 'Trash');
  static String get trashEmpty => _t('Корзина пуста', 'Trash is empty');

  // Google Drive синк
  static String get syncSection => _t(
    'Google Drive — синхронизация задач',
    'Google Drive — task sync',
  );
  static String get syncConnect => _t('Подключить', 'Connect');
  static String get syncDisconnect => _t('Отключить', 'Disconnect');
  static String get syncNowBtn => _t('Синхронизировать', 'Sync now');
  static String get syncConnected => _t('Подключено', 'Connected');
  static String get syncDisconnected => _t('Не подключено', 'Not connected');
  static String get syncSyncing => _t('Синхронизация…', 'Syncing…');
  static String get syncLast => _t('Последний синк', 'Last sync');
  static String get syncClientIdLabel => _t(
    'Client ID (Desktop app)',
    'Client ID (Desktop app)',
  );
  static String get syncClientSecretLabel => _t(
    'Client Secret (Desktop app)',
    'Client Secret (Desktop app)',
  );
  static String get syncServerClientIdLabel => _t(
    'Server Client ID (Web)',
    'Server Client ID (Web)',
  );
  static String get syncFillCredentials => _t(
    'Заполни Client ID и Client Secret: Google Cloud Console → '
        'Credentials → OAuth client «Desktop app». Инструкция — в README.',
    'Fill in Client ID and Client Secret: Google Cloud Console → '
        'Credentials → OAuth client "Desktop app". See README for steps.',
  );
  static String get syncFillServerClientId => _t(
    'Заполни Server Client ID: Google Cloud Console → Credentials → '
        'OAuth client «Web application». Инструкция — в README.',
    'Fill in Server Client ID: Google Cloud Console → Credentials → '
        'OAuth client "Web application". See README for steps.',
  );
  static String get syncRestartNeeded => _t(
    'Server Client ID изменён. Перезапусти приложение, чтобы он вступил '
        'в силу — вход Google настраивается один раз за запуск.',
    'Server Client ID changed. Restart the app for it to take effect — '
        'Google sign-in is configured once per launch.',
  );
  static String get syncDeveloperErrorHint => _t(
    'Google не нашёл OAuth-клиента под это приложение. Проверь в Cloud '
        'Console клиент типа Android: имя пакета com.zfannur.pomodoro_tracker '
        'и SHA-1 ключа, которым подписан APK (gradlew signingReport). '
        'Все клиенты — в одном проекте с включённым Drive API.',
    'Google found no OAuth client for this app. Check the Android client in '
        'Cloud Console: package com.zfannur.pomodoro_tracker and the SHA-1 of '
        'the key the APK is signed with (gradlew signingReport). All clients '
        'must be in one project with the Drive API enabled.',
  );
  static String get syncHint => _t(
    'Задачи хранятся в скрытой папке приложения на твоём Google Drive '
        'и синхронизируются между устройствами.',
    'Tasks are stored in a hidden app folder on your Google Drive '
        'and synced across devices.',
  );

  // Общее
  static String get retry => _t('Повторить', 'Retry');
  static String get errorPrefix => _t('Ошибка: ', 'Error: ');
  static String get loading => _t('Загрузка…', 'Loading…');
}

/// Длительность для UI (в отличие от [formatMinutes] в markdown_codec.dart,
/// который пишет формат в файлы данных — тот всегда русский, это интерфейс).
String formatMinutesUi(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hUnit = S.lang == AppLanguage.ru ? 'ч' : 'h';
  final mUnit = S.lang == AppLanguage.ru ? 'м' : 'm';
  if (h == 0) return '$m$mUnit';
  return m == 0 ? '$h$hUnit' : '$h$hUnit $m$mUnit';
}
