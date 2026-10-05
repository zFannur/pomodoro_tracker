# T06 — Выборочное удаление истории активности

<role>
Flutter-проект `C:\Users\PC\StudioProjects\pomodoro_tracker` (flutter_bloc, equatable, clock).
Трекер активности уже есть. Прочитай целиком: `lib/services/activity_tracker.dart`,
`lib/data/activity_store.dart`, `lib/presentation/cubits/activity_cubit.dart`,
`lib/presentation/screens/activity_screen.dart`, `test/activity_tracker_test.dart`.
Стиль: комментарии на русском, короткие; строки UI только через `S` в `lib/app/strings.dart`
(`_t('рус', 'eng')`, рядом с остальными `activity*`). Минимум кода, повторяй существующие паттерны.
</role>

<task>
На вкладке «Активность» дать пользователю выборочно удалять определённые строки
(приложения / вкладки браузера), а не всю историю.

Данные: `ActivityData.days` (день → `'app|title'` → `ActivityEntry`) и
`ActivityData.focusSegments` (день → список `ActivitySegment` с app/title).
Строка экрана — `ActivityRow` (есть app и title).

1. Чистые функции в `activity_tracker.dart`:
   - `void deleteActivity(ActivityData data, Set<({String app, String title})> items, {String? day})`
     — удаляет записи с этими app+title из `days` и все отрезки с теми же app+title из
     `focusSegments`. `day == null` — во всех днях, иначе только в этом дне («yyyy-MM-dd»).
     Опустевшие дни удалять из обеих карт.
2. `ActivityTracker`: метод `Future<void> delete(items, {String? day})` — вызывает
   `deleteActivity`, ставит `_dirty = true`, сразу `flush()` и шлёт `_ticks.add(null)`.
   Отметку «отвлекающее» (`distracting`) НЕ трогать.
3. `ActivityCubit`: режим выбора в состоянии — `Set<String> selected` (ключ строки `'app|title'`,
   добавь его в `props`). Методы `toggleSelected(row)`, `clearSelection()`,
   `deleteSelected({required bool everywhere})` → `tracker.delete(..., day: everywhere ? null : dateKey(state.date))`,
   затем сброс выбора и `refresh()`. При `prevDay/nextDay` выбор сбрасывать.
4. `activity_screen.dart`:
   - Долгое нажатие (`onLongPress`) на строку — входит в режим выбора и отмечает её.
     В режиме выбора обычный тап переключает отметку (а не «отвлекающее»); слева у строки
     `Checkbox`. Вне режима всё как сейчас (тап — «отвлекающее»).
   - Дополнительно у каждой строки справа `PopupMenuButton` (иконка `more_vert`, size 18) с
     пунктами: «Выбрать» (входит в режим выбора с этой строкой), «Удалить за этот день»,
     «Удалить за все дни». Строка «прочее» без меню и без выбора.
   - В режиме выбора над списком панель: «Выбрано: N», кнопки «Удалить за этот день»,
     «Удалить за все дни», «Отмена». Компактно, `Wrap`, чтобы помещалось на телефоне.
   - Любое удаление — через подтверждение `AlertDialog`: «Удалить N записей за 05.10?» /
     «Удалить N записей за все дни? Это нельзя отменить.», кнопки «Отмена» / «Удалить»
     (кнопка удаления цветом `colorScheme.error`).
5. Тесты в `test/activity_tracker_test.dart` (дописать): `deleteActivity` за один день не трогает
   другие дни; за все дни удаляет везде, включая отрезки; разные title одного браузера
   удаляются раздельно; опустевший день исчезает; `distracting` не меняется.
   Плюс тест `ActivityCubit`: выбор, сброс выбора при смене дня (по образцу существующего
   теста на `segmentsFor`).
</task>

<constraints>
- Не трогать журнал, таймер, синк и другие экраны. Новых зависимостей нет.
- Не менять существующие тесты, только добавлять.
- Перед кодом внимательно прочитай перечисленные файлы.
</constraints>

<done_when>
- `flutter analyze` — без ошибок и предупреждений.
- `flutter test` — все тесты зелёные (запусти сам и убедись).
- Коммит НЕ делать.
</done_when>
