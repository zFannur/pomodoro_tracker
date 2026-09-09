<role>
Flutter-проект `C:\Users\PC\StudioProjects\pomodoro_tracker` (Flutter 3.44 /
Dart 3.12), Windows + Android. Помидоро-таймер с задачником.
Слои: `domain/entities` + `domain/repositories.dart`, `data/`
(`json_data_repository.dart` — истина в `data.json`, `markdown_codec.dart` —
односторонние зеркала в Obsidian, `data_merge.dart` — чистое слияние двух
снимков для синка), `presentation/` (Cubit на `flutter_bloc`).
Ошибки — `Either<Failure, T>` (fpdart). Сущности на `Equatable`.
Тексты ТОЛЬКО в `lib/app/strings.dart` (ru/en), цвета ТОЛЬКО из
`Theme.of(context).colorScheme`. Комментарии по-русски, объясняют ПОЧЕМУ.

Уже существует уровень «Курс» (коммит `e74aa53`): `Direction` и `Milestone`
в `lib/domain/entities/direction.dart` с чистыми функциями `ladder`,
`nextOpen`, `categoryIndex`, `closureRate`, `directionEta`, `closuresByWeek`;
`Sprint.milestoneId` — ссылка недели на ступень лестницы;
`DirectionsCubit`; экран `course_screen.dart`; секции `dirs`/`miles` в
`data.json`; зеркало `Курс.md`. Прочитай эти файлы перед началом.
</role>

<task>
Свяжи ⭐-задачи недели с вехой, которую они двигают. Сейчас ⭐ означает
«обязательство недели», но в данных нигде не сказано, КАКУЮ ступень лестницы
задача закрывает — связь существует только в голове. Из-за этого «Сделано за
неделю» остаётся плоским списком, а не доказательством закрытия ступени.

## 1. `PomoTask.milestoneId`

В `lib/domain/entities/pomo_task.dart` добавь `final String milestoneId;`
(по умолчанию `''`) — веха, которую двигает ⭐-задача. Обнови конструктор,
`copyWith` (добавь `String? milestoneId` и `bool clearMilestoneId = false` —
тот же приём, что у `clearDue`) и `props`.

Сериализация в `lib/data/json_data_repository.dart` (`_taskJson` /
`_taskList`): ключ `'ms'`, пустой опускается. Слияние задач уже идёт по id
целиком, отдельной правки в `data_merge.dart` для этого поля НЕ нужно.

Привязка ставится СНИМКОМ в момент постановки ⭐, а не вычисляется на лету:
веха недели меняется, когда ступень закрывают и в спринт подставляется
следующая, — задача, взятая под ступень 3, не должна молча
переатрибутироваться на ступень 4.

## 2. `Milestone.proofs`

В `lib/domain/entities/direction.dart` добавь
`final List<String> proofs;` (по умолчанию `const []`) — строки закрытых
⭐-задач, которыми ступень закрыта. Формат строки тот же, что у
`Sprint.doneWeek`: `✅ 16.09 Настроить оплату #проекты`.

Сериализация: ключ `'pf'`, пустой список опускается.

**Слияние — отдельной функцией.** Сейчас `data_merge.dart` мержит
`result['miles'] = _mergeById(winner['miles'], loser['miles'])`, а
`_mergeById` при совпадении id берёт версию победителя ЦЕЛИКОМ — значит
доказательство, добавленное на телефоне, исчезнет при слиянии с ПК. Напиши
`_mergeMilestones(win, lose)`: как `_mergeById` по id, но у записей с
одинаковым id `proofs` объединяются через существующий `_mergeValues`
(порядок победителя первым, дубликаты по значению схлопываются — ровно как
`done` у спринтов). Замени вызов для `'miles'` на неё.
`_purge` для `'miles'` оставь как есть.

## 3. Постановка и снятие ⭐ — `lib/presentation/cubits/tasks_cubit.dart`

- В конструктор `TasksCubit` добавь параметр `String Function()
  currentMilestoneId` (в `lib/main.dart` передай
  `() => sprintCubit.state.sprint?.milestoneId ?? ''`). Именно так, а не
  ссылкой на `SprintCubit`: `SprintCubit` уже зависит от
  `tasksCubit.weekTasks`, прямая ссылка обратно замкнула бы цикл.
- `toggleWeek`: при ПОСТАНОВКЕ ⭐ задача получает
  `milestoneId: currentMilestoneId()`; при СНЯТИИ — `clearMilestoneId: true`.
- `clearWeekFlags()` (сброс ⭐ при смене недели) снимает и `milestoneId`.
- `_notifyWeeklyClosed`: расширь колбэк
  `Future<void> Function(String line)? onWeeklyClosed` до
  `Future<void> Function(String line, String milestoneId)?` и передавай
  `task.milestoneId`.

## 4. Доказательство уезжает в веху — `lib/presentation/cubits/directions_cubit.dart`

Добавь `Future<void> addProof(String milestoneId, String line)`: находит веху,
дописывает строку в `proofs`, если её там ещё нет, сохраняет через `_save`.
Пустой `milestoneId` или ненайденная веха — тихо ничего не делает.

В `lib/main.dart` перепиши проводку:

    tasksCubit.onWeeklyClosed = (line, milestoneId) async {
      await sprintCubit.addDoneWeek(line);
      await directionsCubit.addProof(milestoneId, line);
    };

## 5. Экран «Спринт» — `lib/presentation/screens/sprint_screen.dart`

- В карточке вехи, когда веха взята из лестницы, под названием ступени
  добавь строку-счётчик: сколько ⭐-задач сейчас привязано к ЭТОЙ вехе
  (`weekTasks` с совпадающим `milestoneId`) и сколько доказательств уже
  собрано (`milestone.proofs.length`). Строка вида
  «⭐ 2 задачи · закрыто 1» — тексты через `S`.
- В существующей секции «Задачи недели» пометь задачи, привязанные к текущей
  вехе спринта: тонкая иконка/точка в цвете `colorScheme.primary` с тултипом
  «двигает веху недели». ⭐-задачи, привязанные к ДРУГОЙ вехе (поставлены до
  того, как ступень сменилась), пометки не получают — врать про них нельзя.
- Ничего из существующего поведения секции не ломай.

## 6. Экран «Курс» — `lib/presentation/screens/course_screen.dart`

В раскрытой лестнице у ЗАКРЫТОЙ вехи с непустыми `proofs` показывай их
списком мелким приглушённым текстом под названием ступени (без чекбоксов,
это летопись, а не задачи). У открытой вехи с уже набранными
доказательствами — так же. Если `proofs` пуст, лишних отступов не добавляй.

## 7. Зеркало `Курс.md` — `lib/data/markdown_codec.dart`

В `serializeCourse` под строкой вехи выводи её доказательства с отступом:

    - [x] Бот отвечает на 3 команды в проде `2026-W37`
      - ✅ 16.09 Написать обработчик /start #проекты
      - ✅ 17.09 Выкатить на прод #проекты

Пустой список — ни одной строки, никаких пустых буллетов.

## 8. Тесты

- `test/course_merge_test.dart` (дополни): `proofs` двух устройств
  объединяются, а не теряются; дубликат по значению схлопывается.
- `test/directions_cubit_test.dart` (дополни): `addProof` не дублирует строку,
  игнорирует пустой id и несуществующую веху.
- Новый `test/star_milestone_test.dart`: постановка ⭐ проставляет
  `milestoneId` текущего спринта; снятие ⭐ его очищает; `clearWeekFlags`
  очищает и флаг, и привязку; закрытие ⭐-задачи кладёт строку и в
  `Sprint.doneWeek`, и в `proofs` вехи. Фейки — по образцу
  `test/screen_fakes.dart` и `test/sprint_milestone_test.dart`.
- `test/markdown_codec_test.dart` (дополни): доказательства попадают в
  `Курс.md` с отступом, пустой список не даёт лишних строк.
</task>

<constraints>
- Существующее поведение ⭐ (сброс при смене недели, «Сделано за неделю»,
  снапшот задач недели в зеркале спринта) обязано сохраниться полностью.
- Задачи без ⭐ поля `milestoneId` не получают и не теряют.
- Старый `data.json` без ключей `ms` и `pf` читается без ошибок.
- Никаких хардкод-строк и хардкод-цветов.
- Новых пакетов не добавлять.
- Все 200 существующих тестов остаются зелёными.
- Комментарии по-русски, объясняют ПОЧЕМУ.
</constraints>

<done_when>
- `flutter analyze` — 0 issues;
- `flutter test` — всё зелёное, тестов стало минимум на 10 больше;
- поставив ⭐ на задачу при выбранной вехе недели и закрыв эту задачу, видишь
  её строку и в «Сделано за неделю», и под ступенью на экране «Курс», и в
  `Курс.md`.
</done_when>
