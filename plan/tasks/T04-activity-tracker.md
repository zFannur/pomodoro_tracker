# T04 — Трекер активности (Windows): какое приложение/окно сколько времени

<role>
Flutter-проект `C:\Users\PC\StudioProjects\pomodoro_tracker` (Windows + Android, Dart 3.12,
flutter_bloc, equatable, path_provider, intl, clock, win32 ^5.15 уже в зависимостях).
Стиль: комментарии на русском, короткие и по делу; строки UI — только через `S` в
`lib/app/strings.dart` (`_t('рус', 'eng')`). Минимум файлов и абстракций.
</role>

<task>
Новая вкладка «Активность» (Activity): автоматический учёт, в каком приложении и окне
пользователь проводит время, плюс привязка к помодоро-сессиям.

1. `lib/services/activity_tracker.dart` — только Windows (`Platform.isWindows`, иначе no-op):
   - `Timer.periodic` каждые 5 с: `GetForegroundWindow` → `GetWindowThreadProcessId` →
     `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageName` → имя exe
     (без пути, например `chrome.exe`); заголовок окна через `GetWindowTextLength`/`GetWindowText`.
     Не забыть `CloseHandle` и `free()` для выделенной памяти (package:ffi идёт через win32;
     если `ffi` не прямая зависимость — добавь `ffi` в pubspec, это часть Dart SDK-экосистемы).
   - Простой: `GetLastInputInfo` + `GetTickCount`; если ввода не было > 120 с — тик не считается.
   - Для браузеров (chrome.exe, msedge.exe, firefox.exe, brave.exe, opera.exe) из заголовка
     срезать хвост « - Google Chrome» / « — Mozilla Firefox» и т.п. — остаётся название вкладки.
     Для остальных приложений заголовок не хранить (только exe) — меньше данных и шума.
   - Каждый тик добавляет 5 с в агрегат дня: ключ `app` (exe) и, для браузеров, `title`.
     Логическая дата дня — `logicalDate()` из `lib/domain/entities/pomo_session.dart` (сутки с 05:00).
   - Если идёт помидор (TimerCubit: `state.running && state.mode == TimerMode.pomodoro`),
     секунды дополнительно копятся в `focusSeconds` этого же ключа. Трекер получает геттер
     `bool Function() inPomodoro`, а не сам Cubit.
   - Время брать через `clock.now()` (пакет clock), чтобы тесты могли подменять.
2. Хранение — `lib/data/activity_store.dart` по образцу `lib/data/timer_state_store.dart`:
   `getApplicationSupportDirectory()/activity.json`, запись через `.tmp` + `rename`,
   формат `{ "2026-10-05": [ {"app":"chrome.exe","title":"YouTube","seconds":120,"focusSeconds":30}, ... ] }`.
   Сброс на диск не чаще раза в 60 с и при `dispose`. Хранить последние 60 дней, старше — удалять.
   В Drive-синк НЕ добавлять (это локальные данные машины).
3. Классификация: `Set<String>` «отвлекающих» ключей (exe или title браузера) в том же
   activity.json под ключом `"distracting"`. Клик по строке в списке переключает отметку.
4. `lib/presentation/cubits/activity_cubit.dart` — состояние: выбранная дата, список записей
   дня (отсортирован по seconds убыв.), множество distracting. Методы: `refresh()`,
   `prevDay()/nextDay()`, `toggleDistracting(key)`. Обновлять раз в 30 с, пока экран открыт,
   либо по стриму из трекера — что проще.
5. `lib/presentation/screens/activity_screen.dart`:
   - Шапка: дата с ‹ › , итог «Всего X ч Y мин · отвлечения Z% · в помидорах фокус N%»
     (фокус = доля focusSeconds не-отвлекающих от всех focusSeconds).
   - Список: строка = иконка/название (exe без `.exe`, для браузера — «Chrome: title»),
     горизонтальная полоса доли от максимума (`LinearProgressIndicator` или `FractionallySizedBox`),
     время `1 ч 05 мин`. Отвлекающие подсвечены `colorScheme.error`. Топ-50, остальное «прочее».
   - Не Windows: заглушка-текст «Трекер активности пока работает только на Windows».
   - Пустой день: «Нет данных за этот день».
6. `lib/presentation/home_shell.dart`: шестая вкладка после «Статистика» в ОБОИХ шеллах
   (`_narrowShell`, `_wideShell`) и в `IndexedStack`. Иконка — Material `Icons.timelapse`
   в стиле `_courseIcon` (Opacity 0.45 у неактивной). Подпись `S.navActivity`.
7. `lib/main.dart`: создать store, трекер (`inPomodoro: () => timerCubit.state.running && timerCubit.state.mode == TimerMode.pomodoro`),
   `ActivityCubit`, добавить `BlocProvider.value` в `MultiBlocProvider`. Трекер стартует при
   запуске приложения.
8. Тест `test/activity_tracker_test.dart`: агрегация без WinAPI — вынеси чистую функцию
   (например `void addTick(Map<...> day, {app, title, seconds, inFocus})` и
   `String browserTabTitle(String exe, String windowTitle)`) и проверь её: суммирование, focus,
   срез суффикса браузера, игнор заголовка для не-браузеров, удаление дней старше 60.
</task>

<constraints>
- Не трогать существующую логику таймера, синка, задач. Не менять существующие тесты.
- Никаких новых зависимостей, кроме `ffi` при необходимости.
- Никаких LLM/MiniCPM, Chrome-расширений и Android-части — это следующие этапы.
- Если существующий тест на `HomeShell` считает вкладки — поправь только под 6 вкладок.
- Перед написанием кода внимательно прочитай `home_shell.dart`, `main.dart`,
  `timer_state_store.dart`, `strings.dart`, `stats_screen.dart` и повтори их паттерны.
</constraints>

<done_when>
- `flutter analyze` — без новых ошибок и предупреждений.
- `flutter test` — все тесты зелёные, включая новый.
- `flutter build windows --debug` собирается.
- Коммит НЕ делать — только изменения в рабочем дереве.
</done_when>
