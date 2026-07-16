/// Все строки интерфейса. Приложение локальное, язык один — русский.
/// ponytail: i18n-каркас не нужен, при втором языке — flutter_localizations.
abstract final class S {
  static const appTitle = 'Помодоро Трекер';

  // Навигация
  static const navTimer = 'Таймер';
  static const navSprint = 'Спринт';
  static const navStats = 'Статистика';

  // Таймер
  static const pomodoroWord = 'ПОМИДОР';
  static const takeShortBreak = 'Пора сделать короткий перерыв.';
  static const takeLongBreak = 'Пора сделать длинный перерыв.';
  static const shortBreakTitle = 'КОРОТКИЙ ПЕРЕРЫВ';
  static const longBreakTitle = 'ДЛИННЫЙ ПЕРЕРЫВ';
  static const breakWord = 'перерыв';
  static const series = 'серия';
  static const start = 'Старт';
  static const stop = 'Стоп';
  static const pause = 'Пауза';
  static const resume = 'Продолжить';
  static const doneEarly = 'Готово';
  static const skip = 'Пропустить';
  static const delayLabel = 'ЗАДЕРЖКА';
  static const prolong = '+1 мин (Shift — +5)';
  static const forwardHint = 'Прокрутить фазу';
  static const fullscreen = 'Полный экран';
  static const hintKeys =
      'Space — старт/пауза · Esc Esc — стоп/пропуск · +/− — помидоры первой задачи (Shift — ×4)';

  // Задачи
  static const planned = 'Запланировано';
  static const categoryHint = 'Категория';
  static const descriptionHint = '#категория описание ~помидоры';
  static const add = 'Добавить';
  static const planner = 'Планировщик';
  static const emptyPlanned = 'Список планирования пуст.';
  static const emptyPlannedHint = 'Добавьте задачи через форму выше.';
  static const finishTime = 'ВРЕМЯ ОКОНЧАНИЯ';
  static const nextLongBreak = 'Следующий длинный перерыв';
  static const categories = 'Категории';
  static const hintTasks =
      'Клик — редактирование. Клик по числу — +помидор (Alt — минус, Shift — ×4). Перетаскивайте для сортировки.';
  static const menuAddPomo = 'Добавить помидор';
  static const menuRemovePomo = 'Убрать один';
  static const menuMarkDone = 'Отметить как выполненное';
  static const menuCloseWhole = 'Закрыть задачу целиком';
  static const menuSplit = 'Разбить';
  static const menuMerge = 'Объединить';
  static const menuToInbox = 'Во входящие';
  static const menuToTomorrow = 'Перенести на завтра';
  static const menuToLater = 'Перенести на позже';
  static const delete = 'Удалить';
  static const close = 'Закрыть';
  static const cancel = 'Отмена';
  static const editTask = 'Редактировать задачу';
  static const confirmClear = 'Точно очистить? Действие необратимо.';
  static const withoutNote = 'Без заметки';
  static const emptyBucket = 'Пусто';
  static const listSettings = 'Настроить';
  static const tasksTopLabel = 'Новые задачи — наверх';
  static const completeRemoveLabel = 'Снимать задачу при завершении помидора';
  static const clearList = 'Очистить список';
  static const toToday = 'В «Сегодня»';
  static const save = 'Сохранить';

  // Сделано
  static const doneTitle = 'Сделано';
  static const focusLabel = 'фокус';
  static const delaysLabel = 'задержки';
  static const interruptionsLabel = 'прерывания';
  static const manualMark = 'вручную';
  static const goalLine = 'Цель дня';
  static const goalLeft = 'осталось';
  static const menuRepeat = 'Повторить';
  static const menuFillBlanks = 'Заполнить пустые';
  static const emptyDone = 'Сегодня ещё нет помидоров.';
  static const todoEmptyDone = 'Отличная работа! Список задач пуст.';
  static const goalCompleted = 'Поздравляем! Дневная цель выполнена.';
  static const dayCleared = 'Новый день — список «Сделано» начат заново.';

  // Планировщик (корзины — это СРОКИ, не спринт)
  static const inbox = 'Входящие';
  static const tomorrow = 'Завтра';
  static const week = 'Эта неделя';
  static const later = 'Позже';

  // Неделя (спринт)
  static const sprintGoal = 'Цель недели (🍅)';
  static const sprintFact = 'Факт';
  static const sprintByDay = 'По дням';
  static const sprintHistory = 'Прошлые недели';
  static const sprintVelocity = 'Темп';
  static const perDay = '🍅/день';
  static const forecast = 'Прогноз';
  static const milestone = 'Веха недели';
  static const milestoneHint =
      'Тонкий срез до реальности, проверяется бинарно: «товар покупается живым юзером»';
  static const weekTasksTitle = 'Задачи спринта (⭐)';
  static const weekTasksEmpty =
      'Отметь 2–3 задачи звездой в Планировщике (кнопка «Выбрать») — они двигают веху. '
      'В новую неделю звёзды снимаются автоматически.';
  static const pickWeekTasks = 'Выбрать';
  static const plannerHint =
      '🐸 и ⭐ ставятся здесь. Корзины (Завтра/Эта неделя/Позже) — это сроки; '
      'спринт — только ⭐: 3 задачи из текущей вехи.';
  static const doneWeekTitle = 'Сделано за неделю';

  // Система фокуса
  static const nowLabel = 'СЕЙЧАС';
  static const nowEmpty = 'Возьми одну задачу — верхняя в списке и есть СЕЙЧАС';
  static const frogLabel = '🐸 Лягушка дня — делается первой';
  static const frogRemove = 'Убрать лягушку';
  static const weekMark =
      '⭐ В спринт — двигает веху недели (снимается в новую неделю)';
  static const weekUnmark = 'Убрать из спринта';
  static const toInbox = 'Сразу во «Входящие»';
  static const dayOverload =
      'По системе: 🐸 + 2 задачи на день. Лишнее — во «Входящие» (меню ⋮).';
  static const stuckHint = 'Застрял? Разбей до шага на 5 минут — и стартуй.';
  static const whereStopped = 'На чём встал?';
  static const whereStoppedHint =
      'Одна строка — чтобы завтра не вспоминать (можно пропустить)';
  static const notesTitle = 'Заметки';
  static const overtime = 'поток';

  // Статистика
  static const periodToday = 'Сегодня';
  static const periodWeek = 'Неделя';
  static const periodMonth = 'Месяц';
  static const periodYear = '365 дней';
  static const periodCustom = 'Диапазон';
  static const statPomodoros = 'Помидоры';
  static const statFocus = 'Фокус';
  static const statTime = 'Время';
  static const statStreak = 'Серия дней';
  static const statBestDay = 'Лучший день';
  static const statFrog = '🐸 Лягушки';
  static const statFrogHint = 'дней, где сделал главное';
  static const statByCategory = 'По категориям';
  static const statLast14 = 'Последние 14 дней';
  static const statHeatmap = 'Карта активности';
  static const statEmpty = 'Пока нет ни одного помидора за период.';
  static const daysSuffix = 'дн.';

  // Настройки
  static const settings = 'Настройки';
  static const tabTimer = 'Таймер';
  static const tabNotify = 'Оповещения';
  static const tabApp = 'Приложение';
  static const settingsSchemes = 'Схемы';
  static const schemeName = 'Название схемы';
  static const pomodoroLen = 'Продолжительность помидора, мин';
  static const shortLen = 'Короткий перерыв, мин';
  static const longLen = 'Длинный перерыв, мин';
  static const longEvery = 'Длинный перерыв через каждые N помидоров';
  static const autostartPomodoro = 'Автостарт помидора после перерыва';
  static const autostartBreak = 'Автостарт перерыва после помидора';
  static const autostartIfTodo = 'Автостарт помидора только при наличии задач';
  static const flowtimeLabel =
      'Flowtime: не выбивать из потока (помидор дотикал — таймер тихо считает дальше)';
  static const dailyGoal = 'Цель на день, 🍅 (0 — без цели)';
  static const volume = 'Громкость';
  static const finishSound = 'Финишный звук';
  static const finishMelody = 'Мелодия финиша';
  static const tickingSound = 'Тикающий звук во время помидора';
  static const tickingInBreaks = 'Тикать и в перерывах';
  static const notifications = 'Системные уведомления';
  static const notifyMinuteBefore = 'Предупреждать за минуту до конца';
  static const popupRaiseWindow = 'Поднимать окно, когда фаза окончена';
  static const messages = 'Сообщения';
  static const msgPomodoroHint =
      'Тексты для «Помидор завершён» — по одному на строку, выбирается случайный';
  static const msgBreakHint = 'Тексты для «Перерыв окончен»';
  static const telegram = 'Telegram';
  static const telegramToken = 'Токен бота';
  static const telegramChatId = 'Chat ID';
  static const notifyTelegram = 'Дублировать уведомления в Telegram';
  static const sendTest = 'Отправить тестовое оповещение';
  static const testNotification = 'Проверка уведомлений';
  static const themeMode = 'Цветовая схема';
  static const themeLight = 'Светлая';
  static const themeDark = 'Тёмная';
  static const themeSystem = 'Системная';
  static const themeAuto = 'Авто';
  static const dateFormat = 'Формат даты';
  static const timeFormat = 'Формат времени';
  static const storageFolder = 'Папка хранения (markdown)';
  static const chooseFolder = 'Выбрать…';
  static const newCategory = 'Новая категория';
  static const boundScheme = 'Схема категории';
  static const defaultScheme = 'по умолчанию';
  static const sprintGoalDefault = 'Цель спринта по умолчанию, 🍅';
  static const addScheme = 'Добавить схему';
  static const notifyMinuteLeft = 'Осталась минута';
  static const notifyPomodoroDone = 'Помидор завершён!';
  static const notifyBreakDone = 'Перерыв окончен';
  static const notifyBreakDoneBody = 'Следующий помидор будет лучше!';

  // Общее
  static const retry = 'Повторить';
  static const errorPrefix = 'Ошибка: ';
  static const loading = 'Загрузка…';
}
