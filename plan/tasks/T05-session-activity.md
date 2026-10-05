# T05 — Какие программы работали во время конкретного помидора

<role>
Flutter-проект `C:\Users\PC\StudioProjects\pomodoro_tracker` (Windows + Android, flutter_bloc,
equatable, clock). Трекер активности уже есть (коммит e448d78): прочитай целиком
`lib/services/activity_tracker.dart`, `lib/data/activity_store.dart`,
`lib/presentation/cubits/activity_cubit.dart`, `lib/presentation/screens/activity_screen.dart`,
`test/activity_tracker_test.dart` и класс `_DoneRow` в `lib/presentation/screens/timer_screen.dart`.
Стиль: комментарии на русском, короткие; строки UI только через `S` в `lib/app/strings.dart`
(`_t('рус', 'eng')`). Минимум кода и абстракций, повторяй существующие паттерны.
</role>

<task>
Сейчас трекер хранит только суммы за день и не знает, какой помидор что видел. Нужно: в списке
«Сделано» на экране таймера открыть запись помидора и увидеть, какие приложения/вкладки были
активны во время него.

Подход — таймлайн отрезков, без связи с журналом по id (запись помидора и её `start` правятся
анти-накруткой и вручную, поэтому сопоставляем по пересечению интервалов):

1. `activity_store.dart`: в `ActivityData` добавь `focusSegments` — день «yyyy-MM-dd» → список
   `ActivitySegment {DateTime from; DateTime to; String app; String title}`. JSON:
   `"segments": {"2026-10-05": [{"from": "<iso8601>", "to": "<iso8601>", "app": "chrome.exe", "title": "YouTube"}]}`
   — отдельным верхнеуровневым ключом `"segments"`, как сейчас `"distracting"`; `fromJson`
   должен пропускать этот ключ при разборе дней (сейчас он пропускает только `distracting`,
   а не-List значения уже отбрасываются — проверь, что segments не превращается в день).
   Старый activity.json без `segments` должен читаться без ошибок.
2. `activity_tracker.dart`: чистая функция
   `void addSegmentTick(List<ActivitySegment> day, {required DateTime now, required String app, required String title, required int seconds})`:
   если последний отрезок того же app+title и `now - last.to <= seconds*2` с — продлить `last.to = now`,
   иначе добавить новый отрезок `[now - seconds, now]`. В `_record` вызывать её только когда
   `inPomodoro()` == true. `pruneDays` применять и к segments.
3. Чистая функция `List<ActivityRow-подобные записи> segmentsSummary(List<ActivitySegment> all, DateTime from, DateTime to)`:
   суммирует секунды пересечения каждого отрезка с [from, to] по ключу app+title, сортирует по
   убыванию. Окно помидора: `from = session.start - 1 мин`, `to = session.start + minutes + 1 мин`
   (запас на округление минут). Отрезки брать за `dateKey(logicalDate(session.start))`.
4. В `ActivityCubit` метод `segmentsFor(PomoSession s)` → результат п.3 (данные из `_tracker.data`).
5. `timer_screen.dart`, `_DoneRow`: в PopupMenu пункт `'activity'` с текстом `S.menuSessionActivity`
   («Что было открыто» / «What was open») — только на Windows (`Platform.isWindows`).
   По нему `showDialog` с `AlertDialog`: заголовок — задача помидора, список строк
   «Chrome: YouTube — 4 мин» / «Code — 18 мин» (имя: exe без `.exe`, для браузеров
   `browserNames[exe]: title` — как в activity_screen.dart, вынеси общий форматтер имени в
   activity_screen.dart как top-level функцию и используй в обоих местах), отвлекающие
   (`state.distracting`) подсвечены `colorScheme.error`. Пусто — текст `S.sessionActivityEmpty`
   («Нет данных: трекер не работал во время этого помидора»). Кнопка «Закрыть».
   ActivityCubit берётся через `context.read<ActivityCubit>()`.
6. Тесты в `test/activity_tracker_test.dart` (дописать, существующие не ломать):
   склейка тиков в один отрезок, разрыв при смене приложения и при паузе > 2 тиков,
   `segmentsSummary` с частичным пересечением окна, round-trip JSON с segments,
   чтение старого JSON без segments, pruneDays чистит segments.
</task>

<constraints>
- Не трогать журнал, TasksCubit, TimerCubit, PomoSession, синк. Никаких новых зависимостей.
- Не менять существующие тесты, кроме добавления новых в activity_tracker_test.dart.
- Если тесты экранов (`test/timer_screen_test.dart`) падают из-за отсутствия ActivityCubit в
  дереве — сделай пункт меню устойчивым: показывать его только если ActivityCubit доступен
  (например через `context.read<ActivityCubit?>()` не работает в bloc — используй
  try/catch на `ProviderNotFoundException` или передай флаг), но лучше добавить ActivityCubit
  в фейки тестов `test/screen_fakes.dart`, если они собирают дерево провайдеров.
- Перед кодом внимательно прочитай перечисленные файлы. Подумай над краевыми случаями
  (смена суток в 05:00 посреди помидора — допустимо брать отрезки только за день start).
</constraints>

<done_when>
- `flutter analyze` — без ошибок и предупреждений.
- `flutter test` — все тесты зелёные (запусти и убедись сам).
- Коммит НЕ делать.
</done_when>
