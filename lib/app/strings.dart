import '../domain/entities/app_settings.dart';
import '../domain/entities/episode.dart';
import '../domain/entities/experiment.dart';

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
  static String get navInsight => _t('Разбор', 'Review');

  // Таймер
  static String get pomodoroWord => _t('ПОМИДОР', 'POMODORO');
  static String get warmupTitle => _t('РАЗГОН', 'WARM-UP');
  static String get warmupDoneTitle => _t('Разгон пройден', 'Warm-up complete');
  static String get warmupDoneBody => _t(
    'Продолжай, пока идёт. «Готово» — когда хватит.',
    'Keep going while it flows. Press Done when you have had enough.',
  );
  static String get fieldFirstStep => _t('Первый шаг (≤5 мин)', 'First step (≤5 min)');
  static String get startPlan => _t('План старта', 'Start plan');
  static String get cueLabel => _t('Когда…', 'When…');
  static String get cueHint =>
      _t('сяду после завтрака', 'I sit down after breakfast');
  static String get addTime => _t('+ время', '+ time');
  static String remindAt(String time) =>
      _t('Напомнить в $time', 'Remind at $time');
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
  static String get kanban => _t('Канбан', 'Kanban');
  static String get categoryHint => _t('Категория', 'Category');
  static String get descriptionHint =>
      _t('#категория описание ~помидоры', '#category description ~pomodoros');
  static String get add => _t('Добавить', 'Add');
  static String get planner => _t('Планировщик', 'Planner');
  static String get emptyPlanned =>
      _t('Список планирования пуст.', 'The plan is empty.');
  static String get emptyPlannedHint => _t(
    'Добавьте задачи через форму выше.',
    'Add tasks using the form above.',
  );
  static String get finishTime => _t('ВРЕМЯ ОКОНЧАНИЯ', 'FINISH TIME');
  static String get nextLongBreak =>
      _t('Следующий длинный перерыв', 'Next long break');
  static String get categories => _t('Категории', 'Categories');
  static String get hintTasks => _t(
    'Клик — редактирование. Клик по числу — +помидор (Alt — минус, Shift — ×4). Перетаскивайте для сортировки.',
    'Click — edit. Click the number — +pomodoro (Alt — minus, Shift — ×4). Drag to reorder.',
  );
  static String get menuAddPomo => _t('Добавить помидор', 'Add a pomodoro');
  static String get menuRemovePomo => _t('Убрать один', 'Remove one');
  static String get menuMarkDone =>
      _t('Отметить как выполненное', 'Mark as done');
  static String get menuCloseWhole =>
      _t('Закрыть задачу целиком', 'Close the whole task');
  static String get menuSplit => _t('Разбить', 'Split');
  static String get menuMerge => _t('Объединить', 'Merge');
  static String get menuToInbox => _t('Во входящие', 'To inbox');
  static String get menuToTomorrow =>
      _t('Перенести на завтра', 'Move to tomorrow');
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
  static String get tasksTopLabel =>
      _t('Новые задачи — наверх', 'New tasks go to the top');
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
  static String get emptyDone =>
      _t('Сегодня ещё нет помидоров.', 'No pomodoros yet today.');
  static String get todoEmptyDone => _t(
    'Отличная работа! Список задач пуст.',
    'Great work! The task list is empty.',
  );
  static String get goalCompleted => _t(
    'Поздравляем! Дневная цель выполнена.',
    'Congrats! Daily goal reached.',
  );
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
  static String get weekTasksTitle =>
      _t('Задачи спринта (⭐)', 'Sprint tasks (⭐)');
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

  static String dayDoneTitle(String date) =>
      _t('Сделано $date', 'Done on $date');

  static String get dayDoneEmpty =>
      _t('В этот день записей нет.', 'Nothing logged that day.');
  static String get doneTodayEmpty =>
      _t('Сегодня пока ничего не закрыто', 'Nothing closed today yet');
  static String get noDescription => _t('без описания', 'no description');
  static String get minShort => _t('мин', 'min');

  // Система фокуса
  static String get nowLabel => _t('СЕЙЧАС', 'NOW');
  static String get nowEmpty => _t(
    'Возьми одну задачу — верхняя в списке и есть СЕЙЧАС',
    'Pick one task — the top of the list is NOW',
  );
  static String get frogLabel => _t(
    '🐸 Лягушка дня — делается первой',
    '🐸 Frog of the day — do it first',
  );
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
  static String get stuckHint => _t(
    'Застрял? Разбей до шага на 5 минут — и стартуй.',
    "Stuck? Break it down to a 5-minute step — and start.",
  );
  static String get whereStopped =>
      _t('На чём встал?', 'Where did you leave off?');
  static String get whereStoppedHint => _t(
    'Одна строка — чтобы завтра не вспоминать (можно пропустить)',
    "One line, so you don't have to remember tomorrow (optional)",
  );
  static String get notesTitle => _t('Заметки', 'Notes');
  static String get overtime => _t('поток', 'flow');
  static String get session => _t('Сессия', 'Session');
  static String get until => _t('до', 'by');

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
  static String get statFrogHint =>
      _t('дней, где сделал главное', "days you got the main thing done");
  static String get statByCategory => _t('По категориям', 'By category');
  static String get statLast14 => _t('Последние 14 дней', 'Last 14 days');
  static String get statHeatmap => _t('Карта активности', 'Activity map');
  static String get statEmpty => _t(
    'Пока нет ни одного помидора за период.',
    'No pomodoros in this period yet.',
  );
  static String get daysSuffix => _t('дн.', 'd.');

  // Настройки
  static String get settings => _t('Настройки', 'Settings');
  static String get tabTimer => _t('Таймер', 'Timer');
  static String get tabNotify => _t('Оповещения', 'Notifications');
  static String get tabApp => _t('Приложение', 'App');
  static String get tabKanban => _t('Канбан', 'Kanban');
  static String get kanbanEnabled =>
      _t('Включить режим канбан', 'Enable kanban mode');
  static String get kanbanColumns => _t('Колонки канбана', 'Kanban columns');
  static String get kanbanAddColumn => _t('Добавить колонку', 'Add column');
  static String get kanbanColumnName => _t('Название колонки', 'Column name');
  static String get kanbanNoSprint =>
      _t('Спринт ещё загружается.', 'The sprint is still loading.');
  static String get kanbanLastColumnHint => _t(
    'Последняя колонка считается завершением задачи.',
    'The last column marks a task as complete.',
  );
  static String get kanbanColumnHasTasks => _t(
    'Сначала переместите задачи из этой колонки.',
    'Move the tasks out of this column first.',
  );
  static String get kanbanNoTasks => _t(
    'В текущем спринте пока нет задач ⭐.',
    'There are no ⭐ tasks in the current sprint yet.',
  );
  static String get kanbanDropHere => _t('Вставить сюда', 'Drop here');
  static String get kanbanAddSprintTask => _t(
    'Добавьте задачу в спринт через Планировщик.',
    'Add a task to the sprint through Planner.',
  );
  static String kanbanColumnPercent(int count, int total, int percent) =>
      _t('$percent% · $count из $total', '$percent% · $count of $total');
  static String kanbanDaysLeft(int days, int tasks) => _t(
    'Осталось дней: $days · задач: $tasks',
    'Days left: $days · tasks: $tasks',
  );
  static String kanbanPace(String needed, String actual) => _t(
    'Нужно $needed задач/день · факт $actual/день',
    'Need $needed tasks/day · actual $actual/day',
  );
  static String get settingsSchemes => _t('Схемы', 'Schemes');
  static String get schemeName => _t('Название схемы', 'Scheme name');
  static String get pomodoroLen =>
      _t('Продолжительность помидора, мин', 'Pomodoro length, min');
  static String get shortLen => _t('Короткий перерыв, мин', 'Short break, min');
  static String get longLen => _t('Длинный перерыв, мин', 'Long break, min');
  static String get longEvery => _t(
    'Длинный перерыв через каждые N помидоров',
    'Long break every N pomodoros',
  );
  static String get autostartPomodoro => _t(
    'Автостарт помидора после перерыва',
    'Auto-start pomodoro after a break',
  );
  static String get autostartBreak => _t(
    'Автостарт перерыва после помидора',
    'Auto-start break after a pomodoro',
  );
  static String get autostartIfTodo => _t(
    'Автостарт помидора только при наличии задач',
    'Auto-start pomodoro only if tasks are queued',
  );
  static String get flowtimeLabel => _t(
    'Flowtime: не выбивать из потока (помидор дотикал — таймер тихо считает дальше)',
    "Flowtime: don't break the flow (pomodoro ends — the timer quietly keeps counting)",
  );
  static String get dailyGoal =>
      _t('Цель на день, 🍅 (0 — без цели)', 'Daily goal, 🍅 (0 — no goal)');
  static String get sessionHoursLabel => _t(
    'Длина сессии, ч (список «Сегодня»)',
    'Session length, h (Today list)',
  );
  static String get sessionWindowsLabel =>
      _t('Расписание сессий', 'Session schedule');
  static String get sessionWindowsHint => _t(
    'Задай окна (напр. 10:00–13:00) — список «Сегодня» будет биться по ним, '
        'а не по длине сессии. Хвост за расписанием — по длине сессии.',
    'Set windows (e.g. 10:00–13:00) — the Today list splits by them instead '
        'of the session length. Overflow past the schedule uses the length.',
  );
  static String get addWindow => _t('Добавить окно', 'Add window');
  static String get volume => _t('Громкость', 'Volume');
  static String get finishSound => _t('Финишный звук', 'Finish sound');
  static String get finishMelody => _t('Мелодия финиша', 'Finish melody');
  static String get tickingSound =>
      _t('Тикающий звук во время помидора', 'Ticking sound during a pomodoro');
  static String get tickingInBreaks =>
      _t('Тикать и в перерывах', 'Tick during breaks too');
  static String get notifications =>
      _t('Системные уведомления', 'System notifications');
  static String get notifyMinuteBefore =>
      _t('Предупреждать за минуту до конца', 'Warn one minute before the end');
  static String get nudgeIdleLabel =>
      _t('Напоминать при простое', 'Remind me when idle');
  static String get nudgeDistractionLabel => _t(
    'Сигнал при отвлечении в помидоре',
    'Alert when distracted during a pomodoro',
  );
  static String get nudgeIdleTitle =>
      _t('15 минут без помидора', '15 minutes without a pomodoro');
  static String nudgeIdleBody(String task) =>
      _t('Что мешает начать «$task»?', 'What is keeping you from starting "$task"?');
  static String nudgeDistractTitle(String label) =>
      _t('$label во время помидора', '$label during a pomodoro');
  static String nudgeDistractBody(String task) =>
      _t('Вернуться к „$task“?', 'Return to "$task"?');
  static String get cueTitle => _t('Пора', 'Time to start');
  static String cueBody(String cue, String step) =>
      _t('Когда $cue → $step', 'When $cue → $step');
  static String get popupRaiseWindow => _t(
    'Поднимать окно, когда фаза окончена',
    'Raise the window when a phase ends',
  );
  static String get messages => _t('Сообщения', 'Messages');
  static String get msgPomodoroHint => _t(
    'Тексты для «Помидор завершён» — по одному на строку, выбирается случайный',
    'Texts for "Pomodoro finished" — one per line, a random one is picked',
  );
  static String get msgBreakHint =>
      _t('Тексты для «Перерыв окончен»', 'Texts for "Break finished"');
  static String get telegram => _t('Telegram', 'Telegram');
  static String get telegramToken => _t('Токен бота', 'Bot token');
  static String get telegramChatId => _t('Chat ID', 'Chat ID');
  static String get notifyTelegram => _t(
    'Дублировать уведомления в Telegram',
    'Duplicate notifications to Telegram',
  );
  static String get sendTest =>
      _t('Отправить тестовое оповещение', 'Send a test notification');
  static String get testNotification =>
      _t('Проверка уведомлений', 'Notification test');
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
  static String get storageFolder =>
      _t('Папка хранения (markdown)', 'Storage folder (markdown)');
  static String get mirrorToVaultLabel => _t(
    'Зеркалить задачи в валт («Задачи.md», только просмотр)',
    'Mirror tasks to the vault ("Задачи.md", view-only)',
  );
  static String get chooseFolder => _t('Выбрать…', 'Choose…');
  static String get newCategory => _t('Новая категория', 'New category');
  static String get boundScheme => _t('Схема категории', 'Category scheme');
  static String get defaultScheme => _t('по умолчанию', 'default');
  static String get sprintGoalDefault =>
      _t('Цель спринта по умолчанию, 🍅', 'Default sprint goal, 🍅');
  static String get addScheme => _t('Добавить схему', 'Add scheme');
  static String get notifyMinuteLeft =>
      _t('Осталась минута', 'One minute left');
  static String get notifyPomodoroDone =>
      _t('Помидор завершён!', 'Pomodoro finished!');
  static String get notifyBreakDone => _t('Перерыв окончен', 'Break finished');
  static String get notifyBreakDoneBody =>
      _t('Следующий помидор будет лучше!', 'The next pomodoro will be better!');

  // Таблица истории спринтов, поле минут в диалоге редактирования записи
  static String get sprintWord => _t('Спринт', 'Sprint');
  static String get colWeek => _t('Неделя', 'Week');
  static String get colGoal => _t('Цель', 'Goal');
  static String get minutesField => _t('Минуты', 'Minutes');
  static String pomoClickHint(int minutes) => _t(
    '$minutesм · клик +1 🍅, правый клик −1, Shift ×4',
    '${minutes}m · click +1 🍅, right-click −1, Shift ×4',
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
  static String get syncSection =>
      _t('Google Drive — синхронизация задач', 'Google Drive — task sync');
  static String get syncConnect => _t('Подключить', 'Connect');
  static String get syncDisconnect => _t('Отключить', 'Disconnect');
  static String get syncNowBtn => _t('Синхронизировать', 'Sync now');
  static String get syncConnected => _t('Подключено', 'Connected');
  static String get syncDisconnected => _t('Не подключено', 'Not connected');
  static String get syncSyncing => _t('Синхронизация…', 'Syncing…');
  static String get syncLast => _t('Последний синк', 'Last sync');
  static String get syncClientIdLabel =>
      _t('Client ID (Desktop app)', 'Client ID (Desktop app)');
  static String get syncClientSecretLabel =>
      _t('Client Secret (Desktop app)', 'Client Secret (Desktop app)');
  static String get syncServerClientIdLabel =>
      _t('Server Client ID (Web)', 'Server Client ID (Web)');
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

  // Курс
  static String get navCourse => _t('Курс', 'Course');
  static String get courseDirections => _t('Направления', 'Directions');
  static String get coursePaused => _t('На паузе', 'Paused');
  static String get courseFinished => _t('Закрытые', 'Closed');
  static String get courseLadder => _t('Лестница вех', 'Milestone ladder');
  static String get courseClosures => _t('Лента закрытий', 'Closure feed');
  static String get courseAttention =>
      _t('Внимание за 30 дней', 'Attention over 30 days');
  static String get monthReviewTitle => _t('Месячный разбор', 'Monthly review');

  static String get courseEmptyDirections => _t(
    'Пока ни одного направления. Направление — это цель на 3–12 месяцев; '
        'держи 2–4 активных, остальное — на паузу.',
    'No directions yet. A direction is a 3–12 month goal; '
        'keep 2–4 active, pause the rest.',
  );
  static String get courseEmptyLadder => _t(
    'Лестница пуста. Веха — проверяемый результат на 1–3 недели, а не занятие: '
        '«бот отвечает на 3 команды в проде», а не «работать над ботом».',
    'The ladder is empty. A milestone is a verifiable outcome for 1–3 weeks, not an activity: '
        '"bot responds to 3 commands in prod", not "work on the bot".',
  );

  static String get courseDirection => _t('Направление', 'Direction');
  static String get courseMilestone => _t('Веха', 'Milestone');
  static String get courseAddDirection =>
      _t('Добавить направление', 'Add direction');
  static String get courseAddMilestone => _t('Добавить веху', 'Add milestone');
  static String get coursePause => _t('Пауза', 'Pause');
  static String get courseResume => _t('Вернуть в работу', 'Resume');
  static String get courseCloseDirection =>
      _t('Закрыть направление', 'Close direction');
  static String get courseCloseMilestone =>
      _t('Закрыть веху', 'Close milestone');
  static String get courseReopen => _t('Открыть заново', 'Reopen');
  static String get courseCategories => _t('Категории', 'Categories');
  static String get courseObsidianNote =>
      _t('Заметка в Obsidian', 'Obsidian note');
  static String get courseHorizon => _t('Горизонт', 'Horizon');
  static String get courseNoHorizon => _t('Без горизонта', 'No horizon');
  static String get courseRename => _t('Переименовать', 'Rename');
  static String get courseLadderPassed =>
      _t('лестница пройдена', 'ladder completed');
  static String get courseDeleteMilestoneConfirm =>
      _t('Удалить веху?', 'Delete milestone?');

  static String tooManyDirections(int n) => _t(
    'Активных направлений: $n. Работает 2–4 — остальное лучше на паузу.',
    'Active directions: $n. 2–4 works best — pause the rest.',
  );

  static String ladderProgress(int done, int total) =>
      _t('веха $done из $total', 'milestone $done of $total');

  static String paceLabel(String value) =>
      _t('темп $value вех/мес', 'pace $value milestones/mo');
  static String get noPace => _t('темпа пока нет', 'no pace yet');
  static String etaLabel(String date) =>
      _t('при текущем темпе — к $date', 'at current pace — by $date');

  static String get courseThreadNoDirection =>
      _t('Без направления', 'No direction');

  static String monthReviewClosed(int n) =>
      _t('Закрыто вех за месяц: $n', 'Milestones closed this month: $n');
  static String monthReviewStale(String name, int weeks) => _t(
    '$name не двигалось $weeks недель — пауза или №1?',
    '$name had no movement for $weeks weeks — pause or #1?',
  );
  static String get monthReviewDismiss => _t('Понял', 'Got it');

  static String get customMilestone =>
      _t('Своя формулировка', 'Custom wording');
  static String get makeNumberOne => _t('Сделать №1', 'Make #1');
  static String get toPause => _t('На паузу', 'Pause');
  static String get pickMilestone => _t('Выбрать веху', 'Pick milestone');
  static String get takeNextMilestone =>
      _t('Взять следующую ступень', 'Take next milestone');

  static String milestoneProgressCounter(int tasksCount, int closedCount) {
    final taskWord = switch (tasksCount % 10) {
      1 when tasksCount % 100 != 11 => 'задача',
      2 ||
      3 ||
      4 when tasksCount % 100 < 10 || tasksCount % 100 >= 20 => 'задачи',
      _ => 'задач',
    };
    final taskWordEn = tasksCount == 1 ? 'task' : 'tasks';
    return _t(
      '⭐ $tasksCount $taskWord · закрыто $closedCount',
      '⭐ $tasksCount $taskWordEn · closed $closedCount',
    );
  }

  static String get movesWeeklyMilestone =>
      _t('двигает веху недели', 'moves the weekly milestone');

  static String deleteDirectionConfirm(String name) => _t(
    'Удалить направление $name вместе с его вехами?',
    'Delete direction $name along with its milestones?',
  );

  // Активность
  static String get hourShort => _t('ч', 'h');
  static String get activityWindowsOnly => _t(
    'Трекер активности пока работает только на Windows',
    'Activity tracker only works on Windows for now',
  );
  static String get activityEmpty =>
      _t('Нет данных за этот день', 'No data for this day');
  static String get activityOther => _t('прочее', 'other');
  static String get activityHint => _t(
    'Клик по строке — отметить как отвлекающее (и снять отметку)',
    'Click a row to mark it as distracting (or unmark it)',
  );
  static String activityTotal(String time) => _t('Всего $time', 'Total $time');
  static String activityDistractions(int percent) =>
      _t('отвлечения $percent%', 'distractions $percent%');
  static String activityPomoFocus(int percent) =>
      _t('в помидорах фокус $percent%', 'focus in pomodoros $percent%');
  static String get menuSessionActivity =>
      _t('Что было открыто', 'What was open');
  static String get sessionActivityEmpty => _t(
    'Нет данных: трекер не работал во время этого помидора',
    'No data: activity tracker was not running during this pomodoro',
  );
  // Окна задачи (диалог «Что было открыто» / «Окна задачи»)
  static String get menuTaskWindows => _t('Окна задачи', 'Task windows');
  static String get menuTaskWindowsAll =>
      _t('Окна всей задачи', 'Windows of the whole task');
  static String get windowsNoPomos => _t(
    'По этой задаче ещё не было помидоров',
    'No pomodoros for this task yet',
  );
  static String get windowsEmptyTask => _t(
    'Нет данных: трекер не работал во время этих помидоров',
    'No data: activity tracker was not running during these pomodoros',
  );
  static String get windowsTrackerNote => _t(
    'Трекер работает только на Windows и хранит 60 дней',
    'The tracker works on Windows only and keeps 60 days',
  );
  static String windowsSubtitle(int pomos, String total, String seen) => _t(
    '$pomos ${_pomoWord(pomos)} · $total · трекер видел $seen',
    '$pomos ${pomos == 1 ? 'pomodoro' : 'pomodoros'} · $total · tracker saw $seen',
  );
  static String windowsWork(int percent) =>
      _t('Работа $percent%', 'Work $percent%');
  static String windowsDistractions(int percent) =>
      _t('Отвлечения $percent%', 'Distractions $percent%');
  static String windowsMore(int count) => _t('Ещё $count', '$count more');
  static String get windowsBySession => _t('По помидорам', 'By pomodoro');
  static String get windowsFlagTip =>
      _t('Отметить как отвлекающее', 'Mark as distracting');
  static String windowsSessionLabel(DateTime start, int minutes, String clock) {
    const ruDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = _t(ruDays[start.weekday - 1], enDays[start.weekday - 1]);
    return '$day $clock · $minutes $minShort';
  }

  // Что было вместо задачи (окна вне помидоров)
  static String get menuInstead => _t('Что было вместо', 'What was instead');
  static String insteadRange(String from, String to, {required bool untilPomo}) =>
      untilPomo
      ? _t('$from–$to · до первого помидора', '$from–$to · until the first pomodoro')
      : '$from–$to';
  static String get insteadEmpty => _t(
    'Нет данных: трекер не видел окон в это время',
    'No data: the tracker saw no windows at that time',
  );
  static String get insteadNote => _t(
    'Трекер работает только на Windows, окна вне помидоров хранит 14 дней',
    'The tracker works on Windows only and keeps windows outside pomodoros for 14 days',
  );
  static String get insteadTitle => _t('Вместо задач', 'Instead of tasks');

  static String _pomoWord(int n) => switch (n % 10) {
    1 when n % 100 != 11 => 'помидор',
    2 || 3 || 4 when n % 100 < 10 || n % 100 >= 20 => 'помидора',
    _ => 'помидоров',
  };
  static String get activitySelect => _t('Выбрать', 'Select');
  static String get activityDeleteDay =>
      _t('Удалить за этот день', 'Delete for this day');
  static String get activityDeleteAllDays =>
      _t('Удалить за все дни', 'Delete for all days');
  static String activitySelected(int count) =>
      _t('Выбрано: $count', 'Selected: $count');
  static String activityDeleteConfirmDay(int count, String date) => _t(
    'Удалить $count ${_recordWord(count)} за $date?',
    'Delete $count ${count == 1 ? 'record' : 'records'} for $date?',
  );
  static String activityDeleteConfirmAll(int count) => _t(
    'Удалить $count ${_recordWord(count)} за все дни? Это нельзя отменить.',
    'Delete $count ${count == 1 ? 'record' : 'records'} for all days? This cannot be undone.',
  );
  static String _recordWord(int n) => switch (n % 10) {
    1 when n % 100 != 11 => 'запись',
    2 || 3 || 4 when n % 100 < 10 || n % 100 >= 20 => 'записи',
    _ => 'записей',
  };

  // Откладывание: причины и способы
  static String cause(Cause c) => switch (c) {
    Cause.unclear => _t('Непонятно, с чего начать', 'Not sure where to start'),
    Cause.big => _t('Слишком большая', 'Too big'),
    Cause.boring => _t('Скучно', 'Boring'),
    Cause.perfect => _t('Боюсь сделать плохо', "Afraid it won't be good"),
    Cause.tired => _t('Нет сил', 'No energy'),
    Cause.pointless => _t('Не вижу смысла', "Don't see the point"),
    Cause.external => _t('Отвлекли', 'Interrupted'),
  };
  static String get causeFinished => _t('Доделал', 'Finished');
  static String get episodeTitle => _t('Что мешает?', 'What is getting in the way?');
  static String get episodeTry => _t('Попробуй', 'Try this');
  static String get episodeJustMark => _t('Только отметить', 'Just note it');
  static String get episodeThought => _t('Мысль (по желанию)', 'Thought (optional)');
  static String get observationNote => _t('Неделя наблюдения: просто отмечаем. Способы — со следующей недели.', 'Observation week: just take notes. Strategies start next week.');
  static String get observationHelp => _t('Всё равно помочь →', 'Help anyway →');
  static String get episodeDone => _t('Готово', 'Done');
  static String get episodeOther => _t('Другой способ:', 'Another strategy:');
  static String episodeHelped(int wins, int tries) => _t('Помогало тебе: $wins из $tries раз', 'Helped you: $wins out of $tries times');
  static String get episodeNoStrategies => _t('Для этой причины нужен план задачи. Пока можно только отметить.', 'This reason needs a task plan. For now, just note it.');
  static String get fieldThen => _t('То:', 'Then:');
  static String get stuckChip => _t('Застрял? Что мешает начать →', 'Stuck? What is stopping you →');
  static String get notGoing => _t('Не идёт', 'Not going well');
  static String distractedChip(String app) => _t('Отвлёкся на $app — отметить причину', 'Distracted by $app — note the reason');
  static String get whyStopped => _t('Почему остановился', 'Why did you stop?');
  static String deferralSnack(int n) => _t('Перенос №$n. Разобрать, что мешает?', 'Deferral #$n. Explore what is getting in the way?');
  static String get deferralAction => _t('Разобрать', 'Explore');
  static String deferralsTooltip(int n) => _t('Переносили $n раз', 'Deferred $n times');
  static String deferralsBadge(int n) => _t('↻$n', '↻$n');

  static String strategyTitle(StrategyKind k) => switch (k) {
    StrategyKind.firstStep => _t('Первый шаг на 5 минут', 'First step in 5 minutes'),
    StrategyKind.warmup => _t('Только 10 минут', 'Just 10 minutes'),
    StrategyKind.ifThen => _t('План «если — то»', 'If-then plan'),
    StrategyKind.shrink => _t('Уменьшить задачу', 'Shrink the task'),
    StrategyKind.thought => _t('Проверить мысль', 'Check the thought'),
    StrategyKind.defuse => _t('Взять чувство с собой', 'Take the feeling with you'),
    StrategyKind.value => _t('Зачем это мне', 'Why this matters to me'),
    StrategyKind.rest => _t('Честный отдых', 'Real rest'),
    StrategyKind.removeCue => _t('Убрать раздражитель', 'Remove the distraction'),
  };

  static String strategyBody(StrategyKind k) => switch (k) {
    StrategyKind.firstStep => _t('Запиши самое первое физическое действие: открыть файл, написать одно предложение, найти одну ссылку. Не решение — только вход.', 'Write down the very first physical action: open a file, write one sentence, find one link. Not the solution — just a way in.'),
    StrategyKind.warmup => _t('Договорись с собой на 10 минут. После можно честно остановиться — но обычно не хочется.', 'Commit to 10 minutes. Afterwards you can honestly stop — but usually you will want to continue.'),
    StrategyKind.ifThen => _t('Привяжи начало к ситуации: «Когда ___, я ___». Чем конкретнее ситуация, тем лучше срабатывает.', 'Tie the start to a situation: "When ___, I will ___". The more specific the situation, the better it works.'),
    StrategyKind.shrink => _t('Какая самая маленькая версия ещё считается шагом вперёд? Её — первой.', 'What is the smallest version that still counts as a step forward? Do that first.'),
    StrategyKind.thought => _t('Мысль — это гипотеза, не факт. Что ты знаешь наверняка? Как сказать точнее?', 'A thought is a hypothesis, not a fact. What do you know for sure? How can you put it more accurately?'),
    StrategyKind.defuse => _t('Скажи себе: «Я замечаю мысль, что…». Не надо ждать, пока станет не страшно, — возьми это чувство с собой на 10 минут.', 'Tell yourself: "I notice the thought that…". You do not have to wait until you are no longer afraid — take the feeling with you for 10 minutes.'),
    StrategyKind.value => _t('Показывает «Зачем» направления задачи. Нет направления: «Эта задача не про твои цели. Может, ей место во „Входящих“?»', 'Shows the task direction’s "Why". No direction: "This task is not about your goals. Maybe it belongs in Inbox?"'),
    StrategyKind.rest => _t('10 минут без экрана: вода, окно, пройтись. Потом — разгон.', '10 minutes without a screen: water, a window, a walk. Then warm up.'),
    StrategyKind.removeCue => _t('Закрой вкладку, телефон экраном вниз или в другую комнату. Мысль, которая отвлекла, — во «Входящие».', 'Close the tab, put your phone face down or in another room. Put the distracting thought in Inbox.'),
  };
  static String get actionWarmup => _t('Разгон 10 мин', '10-min warm-up');
  static String get actionSaveWarmup => _t('Сохранить и разгон 10 мин', 'Save and warm up 10 min');
  static String get actionSave => _t('Сохранить', 'Save');
  static String get actionRest => _t('Отдых 10 мин', 'Rest 10 min');
  static String get actionToInbox => _t('Во „Входящие“', 'To Inbox');
  static String get actionAddStart => _t('Добавить и начать', 'Add and start');
  static String get actionContinue => _t('Продолжить', 'Continue');
  static String get fieldCue => _t('Когда…', 'When…');
  static String get fieldCueAt => _t('Напомнить в', 'Remind at');
  static String get fieldShrink => _t('Минимальная версия', 'Smallest version');
  static String get fieldThought => _t('Мысль', 'Thought');
  static String get fieldFact => _t('Что я знаю наверняка', 'What I know for sure');
  static String get fieldAlt => _t('Как сказать точнее', 'A more accurate thought');
  static String get fieldWhy => _t('Зачем мне это направление?', 'Why does this direction matter to me?');
  static String get fieldToInbox => _t('Мысль, которая отвлекла, — во «Входящие»', 'Put the distracting thought in Inbox');
  static String get valueNoDirection => _t('Эта задача не про твои цели. Может, ей место во „Входящих“?', 'This task is not about your goals. Maybe it belongs in Inbox?');
  static String defuseLine(String thought) => _t('Я замечаю мысль, что «$thought»', 'I notice the thought that "$thought"');
  static String metric(InsightMetric m) => switch (m) {
    InsightMetric.firstStart => _t('Первый помидор', 'First pomodoro'),
    InsightMetric.idle => _t('Простой', 'Idle time'),
    InsightMetric.frogFirst => _t('🐸 первой', '🐸 first'),
    InsightMetric.deferrals => _t('Переносы', 'Deferrals'),
    InsightMetric.distract => _t('Отвлечения', 'Distractions'),
    InsightMetric.success => _t('Успех способов', 'Strategy success'),
  };
  static String hypothesis(StrategyKind k, InsightMetric m) {
    final action = switch (k) {
      StrategyKind.firstStep => _t('у задачи есть первый шаг', 'the task has a first step'),
      StrategyKind.warmup => _t('начинать с разгона 10 минут', 'I start with a 10-minute warm-up'),
      StrategyKind.ifThen => _t('у 🐸 есть план „если — то“', '🐸 has an if-then plan'),
      StrategyKind.shrink => _t('уменьшать большую задачу', 'I shrink a large task'),
      StrategyKind.thought => _t('проверять мысль', 'I check the thought'),
      StrategyKind.defuse => _t('брать чувство с собой', 'I take the feeling with me'),
      StrategyKind.value => _t('вспоминать „зачем“', 'I remember why'),
      StrategyKind.rest => _t('отдыхать честно', 'I take real rest'),
      StrategyKind.removeCue => _t('убирать раздражитель', 'I remove the distraction'),
    };
    return _t('Если $action, ${metric(m)} станет лучше', 'If $action, ${metric(m)} will improve');
  }
  static String verdict(Verdict v) => switch (v) {
    Verdict.works => _t('работает', 'works'),
    Verdict.same => _t('без разницы', 'no difference'),
    Verdict.worse => _t('хуже', 'worse'),
    Verdict.unclear => _t('мало данных', 'not enough data'),
  };

  // Разбор
  static String get insightTabWeek => _t('Неделя', 'Week');
  static String get insightTabEpisodes => _t('Эпизоды', 'Episodes');
  static String get insightTabWindows => _t('Окна', 'Windows');
  static String insightWeekTitle(String week) =>
      _t('Неделя $week', 'Week $week');
  static String get insightObservationSuffix =>
      _t('· неделя наблюдения', '· observation week');
  static String get insightNoData => _t('мало данных', 'not enough data');
  static String insightBase(String value) =>
      _t('база: $value', 'baseline: $value');
  static String lagValue(int minutes) => '+$minutes $minShort';
  static String minutesValue(int minutes) => '$minutes $minShort';
  static String get insightCauses => _t('Причины', 'Reasons');
  static String causeBest(String strategy, int wins, int tries) => _t(
    '· лучше всего: $strategy $wins/$tries',
    '· best: $strategy $wins/$tries',
  );
  static String causeExternal(int n) => _t('Отвлекали: $n', 'Interrupted: $n');
  static String get causesEmpty => _t(
    'Пока нет отметок. Сигналы появятся сами, когда таймер стоит, а задачи есть.',
    'No notes yet. Signals will appear on their own when the timer is idle and there are tasks.',
  );
  static String get wellbeingTitle =>
      _t('Самочувствие → дела', 'Well-being → work');
  static String wellbeingLine(
    String field,
    String metric,
    String good,
    String bad,
  ) =>
      '$field ≥4: ${metric.toLowerCase()} $good · ${field.toLowerCase()} ≤2: $bad';
  static String get wellbeingHint => _t(
    'Отмечай сон утром — через 3–4 недели здесь появится связь',
    'Rate your sleep in the morning — in 3–4 weeks a link will show up here',
  );
  static String get experimentTitle => _t('Эксперимент', 'Experiment');
  static String experimentResult(String hypothesis) =>
      _t('Итог: $hypothesis', 'Result: $hypothesis');
  static String experimentWasNow(String metric, String was, String now) => _t(
    '$metric: было $was → стало $now',
    '$metric: was $was → now $now',
  );
  static String experimentCurrent(
    String metric,
    String was,
    String now,
    int days,
  ) => _t(
    '$metric: было $was → сейчас $now · осталось $days дн.',
    '$metric: was $was → now $now · $days d left',
  );
  static String experimentCard(
    String hypothesis,
    String metric,
    String was,
    String now,
  ) => _t(
    '🧪 $hypothesis · $metric: было $was → сейчас $now',
    '🧪 $hypothesis · $metric: was $was → now $now',
  );
  static String verdictButton(Verdict v) => switch (v) {
    Verdict.works => _t('Работает', 'Works'),
    Verdict.same => _t('Без разницы', 'No difference'),
    Verdict.worse => _t('Хуже', 'Worse'),
    Verdict.unclear => _t('Мало данных', 'Not enough data'),
  };
  static String get experimentClear => _t('Снять', 'Drop');
  static String get experimentTake => _t('Взять', 'Take it');
  static String get experimentCustom => _t('Свой…', 'Custom…');
  static String get experimentLater => _t('Не сейчас', 'Not now');
  static String get experimentSuggested =>
      _t('Предложение на неделю', 'Suggestion for the week');
  static String get experimentAfterObservation => _t(
    'Эксперименты начнутся после недели наблюдения',
    'Experiments start after the observation week',
  );
  static String get experimentCustomTitle =>
      _t('Свой эксперимент', 'Custom experiment');
  static String get fieldHypothesis => _t('Гипотеза', 'Hypothesis');
  static String get fieldStrategy => _t('Способ', 'Strategy');
  static String get fieldMetric => _t('Метрика', 'Metric');
  static String get reviewTitle => _t('Разбор недели', 'Week review');

  // Эпизоды (вкладка «Разбор»)
  static String get episodesEmpty =>
      _t('За две недели эпизодов нет', 'No episodes in the last two weeks');
  static String get episodeDeleted => _t('Эпизод удалён', 'Episode deleted');
  static String get episodeNoCause => '—';
  static String episodeDistract(String app) =>
      _t('$app во время помидора', '$app during a pomodoro');
  static String get episodeNoTask => _t('Без задачи', 'No task');
  static String dayHeader(DateTime d) {
    const ruDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ruMonths = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    const enMonths = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return _t(
      '${ruDays[d.weekday - 1]}, ${d.day} ${ruMonths[d.month - 1]}',
      '${enDays[d.weekday - 1]}, ${enMonths[d.month - 1]} ${d.day}',
    );
  }

  // Шкала IPS
  static String get ipsTitle =>
      _t('Шкала откладывания', 'Procrastination scale');
  static String get ipsSubtitle =>
      _t('9 вопросов, 1 минута', '9 questions, 1 minute');
  static String get ipsTake => _t('Пройти', 'Take it');
  static String get ipsLow =>
      _t('1 — совсем не про меня', '1 — very seldom or not true of me');
  static String get ipsHigh =>
      _t('5 — точно про меня', '5 — very often true of me');
  static String monthShort(int m) {
    const ru = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    const en = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return _t(ru[m - 1], en[m - 1]);
  }

  // Пункты IPS: Svartdal & Steel (2017), Frontiers in Psychology 8:1927,
  // CC BY 4.0. Английский — оригинал; русский — неофициальный перевод,
  // не валидирован. Обратные пункты (2, 6, 9) — `ipsReversed` в insights.dart.
  static String ipsItem(int i) => switch (i) {
    0 => _t(
      'Я откладываю дела так долго, что это без необходимости вредит моему благополучию или эффективности',
      'I put things off so long that my well-being or efficiency unnecessarily suffers',
    ),
    1 => _t(
      'Если есть что-то, что мне нужно сделать, я берусь за это раньше, чем за менее важные дела',
      'If there is something I should do, I get to it before attending to lesser tasks',
    ),
    2 => _t(
      'Моя жизнь была бы лучше, если бы я делал некоторые дела или задачи раньше',
      'My life would be better if I did some activities or tasks earlier',
    ),
    3 => _t(
      'Когда мне нужно делать одно, я делаю другое',
      'When I should be doing one thing, I will do another',
    ),
    4 => _t(
      'К концу дня я понимаю, что мог бы потратить время лучше',
      'At the end of the day, I know I could have spent the time better',
    ),
    5 => _t('Я трачу своё время с умом', 'I spend my time wisely'),
    6 => _t(
      'Я откладываю дела дольше, чем это разумно',
      'I delay tasks beyond what is reasonable',
    ),
    7 => _t('Я прокрастинирую', 'I procrastinate'),
    _ => _t(
      'Я делаю всё тогда, когда считаю, что это нужно сделать',
      'I do everything when I believe it needs to be done',
    ),
  };

  // Карточка дня
  static String get dayCardSetting =>
      _t('Карточка дня на таймере', 'Day card on the timer');
  static String get sleepLabel => _t('Сон', 'Sleep');
  static String get energyLabel => _t('Энергия', 'Energy');
  static String get moodQuestion =>
      _t('Как прошёл день?', 'How was your day?');
  static String dotsLabel(String name, int? value) => value == null
      ? _t('$name, не отмечено', '$name, not rated')
      : _t('$name, $value из 5', '$name, $value out of 5');
  static String get yesterdayFrog => _t(
    'Вчера 🐸 не сдвинулась. Так бывает — это про задачу, не про тебя.',
    "Yesterday's 🐸 didn't move. It happens — it's about the task, not you.",
  );
  static String yesterdayDefers(int n) => _t(
    'Вчера $n ${_deferWord(n)}. Посмотрим, что мешало?',
    'Yesterday: $n deferrals. Shall we see what got in the way?',
  );
  static String _deferWord(int n) => switch (n % 10) {
    1 when n % 100 != 11 => 'перенос',
    2 || 3 || 4 when n % 100 < 10 || n % 100 >= 20 => 'переноса',
    _ => 'переносов',
  };
  static String get whatGotInTheWay =>
      _t('Что помешало?', 'What got in the way?');
  static String get firstStepForFrog =>
      _t('Первый шаг для 🐸', 'First step for 🐸');
  static String planLine(String cue, String then, String at) => _t(
    '▸ Когда $cue → $then${at.isEmpty ? '' : ' · $at'}',
    '▸ When $cue → $then${at.isEmpty ? '' : ' · $at'}',
  );

  // ИИ (DeepSeek)
  static String get tabAi => _t('ИИ', 'AI');
  static String get aiEnabledLabel =>
      _t('Подсказки ИИ (DeepSeek)', 'AI hints (DeepSeek)');
  static String get aiKeyLabel => _t('API-ключ', 'API key');
  static String get aiShowKey => _t('Показать ключ', 'Show key');
  static String get aiHideKey => _t('Скрыть ключ', 'Hide key');
  static String get aiGetKey => _t('Получить ключ', 'Get a key');
  static String get aiModelLabel => _t('Модель', 'Model');
  static String get aiModelHint => 'deepseek-flash = V4.1 Flash';
  static String get aiCheck => _t('Проверить', 'Check');
  static String get aiKeyWorks => _t('Ключ работает', 'The key works');
  static String get aiPrivacy => _t(
    'Уходит: текст задачи, мысли из листа эпизода, недельные цифры. '
        'Не уходит: окна, заметки, ключи других сервисов. '
        'Сервер DeepSeek — в Китае.',
    'Sent: task text, thoughts from the episode sheet, weekly numbers. '
        'Not sent: windows, notes, keys of other services. '
        'The DeepSeek server is in China.',
  );
  static String get aiConsentText => _t(
    'Текст задачи и мысли уйдут в DeepSeek (Китай). Продолжить?',
    'The task text and thoughts will be sent to DeepSeek (China). Continue?',
  );
  static String get aiConsentYes =>
      _t('Да, не спрашивать', "Yes, don't ask again");
  static String get aiUnavailable => _t(
    'ИИ выключен или не задан ключ',
    'AI is off or the key is not set',
  );
  static String get aiEmpty =>
      _t('DeepSeek вернул пустой ответ', 'DeepSeek returned an empty answer');
  static String get aiBadKey => _t('Ключ не подходит', 'The key is not valid');
  static String get aiNoBalance =>
      _t('На счёте DeepSeek нет денег', 'Your DeepSeek balance is empty');
  static String get aiBusy => _t(
    'Слишком много запросов, попробуй через минуту',
    'Too many requests, try again in a minute',
  );
  static String get aiError => _t('DeepSeek не ответил', 'DeepSeek did not answer');
  static String get aiRejected => _t(
    'DeepSeek отклонил запрос — проверь модель',
    'DeepSeek rejected the request — check the model',
  );
  static String get aiConcern => _t(
    'Похоже, сейчас тяжело не с задачей. Об этом стоит поговорить с '
        'близким человеком или специалистом.',
    "It sounds like this is about more than the task. It's worth talking "
        'to someone close to you or a professional.',
  );
  static String get aiSuggestStep =>
      _t('Подсказать первый шаг', 'Suggest a first step');
  static String get aiSuggestThought =>
      _t('Подсказать, как сказать точнее', 'Suggest a more accurate thought');
  static String get aiReview => _t('Разбор от ИИ', 'AI review');
  static String get aiReviewRefresh => _t('Обновить', 'Refresh');
  static String thinkingPattern(String name) =>
      _t('Похоже на: $name', 'Looks like: $name');
  static String thinkingPatternName(String id) => switch (id) {
    'all_or_nothing' => _t('всё или ничего', 'all-or-nothing'),
    'catastrophizing' => _t('катастрофизация', 'catastrophizing'),
    'should' => _t('долженствование', 'should statements'),
    'mind_reading' => _t('чтение мыслей', 'mind reading'),
    'discounting' => _t('обесценивание', 'discounting the positive'),
    'overgeneralizing' => _t('сверхобобщение', 'overgeneralizing'),
    _ => '',
  };

  // Общее
  static String get retry => _t('Повторить', 'Retry');
  static String get errorPrefix => _t('Ошибка: ', 'Error: ');
  static String get loading => _t('Загрузка…', 'Loading…');
}

/// Длительность для UI (в отличие от [formatMinutes] в markdown_codec.dart,
/// который пишет формат в файлы данных — тот всегда русский, это интерфейс).
/// «HH:mm» из минут от полуночи, с учётом 12/24ч.
String formatMinutesOfDay(int minOfDay, TimeFmt fmt) =>
    formatClock(DateTime(2000, 1, 1, minOfDay ~/ 60, minOfDay % 60), fmt);

String formatMinutesUi(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hUnit = S.lang == AppLanguage.ru ? 'ч' : 'h';
  final mUnit = S.lang == AppLanguage.ru ? 'м' : 'm';
  if (h == 0) return '$m$mUnit';
  return m == 0 ? '$h$hUnit' : '$h$hUnit $m$mUnit';
}
