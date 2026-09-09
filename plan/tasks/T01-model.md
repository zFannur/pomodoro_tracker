<role>
Ты работаешь в Flutter-проекте `C:\Users\PC\StudioProjects\pomodoro_tracker`
(Flutter 3.44 / Dart 3.12, Windows + Android). Помидоро-таймер с задачником.
Архитектура: domain/entities + domain/repositories.dart (интерфейсы),
data/ (JsonDataRepository — истина в data.json, markdown_codec — зеркала в
Obsidian, data_merge — чистое слияние двух снимков для синка), presentation/
(Cubit на flutter_bloc). Ошибки — `Either<Failure, T>` (fpdart) на границе
репозиториев. Сущности на `Equatable`. Все комментарии и doc-строки — на
русском, стиль: `///` с объяснением ПОЧЕМУ так, а не пересказ кода.
Цвета только в `lib/app/theme.dart`, тексты только в `lib/app/strings.dart`.
</role>

<task>
Добавь в модель уровень выше недели: «Направление» и «Веха» (ступень лестницы).
UI в этой задаче НЕ трогай — только domain + data + тесты.

## 1. Новый файл `lib/domain/entities/direction.dart`

Сущности (полные тела с `copyWith` и `props` напиши сам, по образцу
`lib/domain/entities/sprint.dart`):

    enum DirectionStatus { active, paused, done }

    class Direction extends Equatable {
      const Direction({
        required this.id,
        required this.name,
        this.note = '',
        this.horizon,
        this.status = DirectionStatus.active,
        this.order = 0,
        this.categories = const [],
      });

      final String id;
      final String name;
      final String note;          // имя заметки в Obsidian
      final DateTime? horizon;    // месяц-цель
      final DirectionStatus status;
      final int order;
      final List<String> categories;  // категории задач/помидоров направления
    }

    class Milestone extends Equatable {
      const Milestone({
        required this.id,
        required this.directionId,
        required this.title,
        this.order = 0,
        this.doneSprint = '',
        this.doneAt,
      });

      final String id;
      final String directionId;
      final String title;
      final int order;
      final String doneSprint;   // id недели `2026-W29`; пусто — веха открыта
      final DateTime? doneAt;

      bool get done => doneSprint.isNotEmpty;
    }

`Direction.copyWith` принимает дополнительно `bool clearHorizon = false`,
`Milestone.copyWith` — `bool reopen = false` (снимает `doneSprint` и `doneAt`);
это тот же приём, что уже применён в `PomoTask.copyWith` с `clearDue`.

Смысл, который надо отразить в doc-комментариях:
- пауза направления — явная и важная: она снимает вину за заброшенное
  направление и делает оставшиеся ощутимо движущимися;
- направление держит КАТЕГОРИИ, а не ссылки из задач: поэтому вся прошлая
  история журнала атрибутируется задним числом, без миграции и без нового
  поля в `PomoTask`;
- у вех нет дат, только порядок: на месяцы планируются исходы, а не действия,
  иначе план протухает за две недели;
- веха проверяется бинарно и формулируется как результат, а не деятельность.

Дальше в ЭТОМ ЖЕ файле — чистые функции (так же, как `sessionSplit` живёт
рядом с `PomoTask` в `pomo_task.dart`). Все без IO, все покрыты тестами.
`DayLog` импортируется из `pomo_session.dart`.

    /// Категория → id направления. Категория, попавшая в два направления,
    /// достаётся тому, что раньше по `order`: атрибуция помидора обязана быть
    /// однозначной, иначе доли внимания не сложатся в 100%.
    Map<String, String> categoryIndex(List<Direction> directions);

    /// Вехи направления по возрастанию `order`.
    List<Milestone> ladder(List<Milestone> all, String directionId);

    /// Следующая незакрытая ступень. null — лестница пройдена.
    Milestone? nextOpen(List<Milestone> all, String directionId);

    /// Темп: сколько вех направления закрывается за 30 дней. Считается по
    /// фактическим закрытиям за последние [days] дней, а не по оценкам —
    /// система измеряет реальную скорость, а не обещанную. 0 без закрытий.
    double closureRate(
      List<Milestone> all,
      String directionId,
      DateTime now, {
      int days = 84,
    });

    /// Прогноз закрытия направления при текущем темпе.
    /// null — темпа нет (0 закрытий за окно) либо открытых вех не осталось.
    DateTime? directionEta(List<Milestone> all, String directionId, DateTime now);

    /// Помидоры по направлениям за период. Ключ — id направления;
    /// ключ `''` — помидоры вне направлений.
    Map<String, int> pomosByDirection(List<DayLog> days, List<Direction> directions);

    /// Лента закрытий: id недели (`2026-W29`) → вехи, закрытые в эту неделю.
    Map<String, List<Milestone>> closuresByWeek(List<Milestone> all);

## 2. `lib/domain/entities/sprint.dart`

Добавь в `Sprint` поле `final String milestoneId;` (по умолчанию `''`) —
ссылку на ступень лестницы. Поле `milestone` (текст) ОСТАЁТСЯ: им пользуются
недели вне направлений и все старые данные. Обнови конструктор, `copyWith`
(добавь `String? milestoneId` и `bool clearMilestoneId = false`) и `props`.
Существующее поведение не менять.

## 3. `lib/domain/repositories.dart`

    /// Направления и их лестницы вех — уровень выше недели.
    typedef Course = ({List<Direction> directions, List<Milestone> milestones});

    abstract interface class DirectionRepository {
      Future<Either<Failure, Course>> loadCourse();

      Future<Either<Failure, Unit>> saveCourse(Course course);
    }

## 4. `lib/data/json_data_repository.dart`

- `JsonDataRepository` дополнительно реализует `DirectionRepository`
  (он уже реализует три интерфейса сразу — они читают один документ).
- В `_Doc`: `final List<Direction> directions;` и `final List<Milestone> milestones;`
  (пустые списки в `_Doc.empty()`).
- В `_Doc._known` добавь `'dirs'` и `'miles'`.
- `_Doc.decode` разбирает эти секции, `_Doc.encode` пишет. Формат компактный,
  как у соседей (смотри `_taskJson`), необязательные ключи опускаются:
  - направление: `{'id','name','note'?,'hor'? (dateKey),'st':'active|paused|done',
    'ord', 'cats': ['работа', ...]}`; неизвестный `st` читается как `active`;
  - веха: `{'id','dir','t','ord','ws'? (id недели),'wa'? (dateKey)}`.
- `ids()` ОБЯЗАН включать id направлений и вех: иначе удаление не попадёт в
  надгробия и удалённое направление воскреснет при следующем слиянии.
- `loadCourse()` / `saveCourse()` — по образцу `load()` / `saveTasks()`:
  через `_load()` и `_write(doc, before: ...)` со снимком id ДО правки.
  Посмотри, как `saveTasks` считает `before` и как работает `_servedTasks`,
  и повтори этот путь один в один, включая `onSaved`.
- Зеркала в валт в этой задаче НЕ трогай.

## 5. `lib/data/data_merge.dart`

- Слияние новых секций рядом с существующими:
  `result['dirs'] = _mergeById(winner['dirs'], loser['dirs']);`
  `result['miles'] = _mergeById(winner['miles'], loser['miles']);`
- `_purge` обязан вычитать похороненные id и из `dirs`, и из `miles` —
  иначе delete-wins на них не работает.

## 6. Тесты

Новый файл `test/course_test.dart` — чистые функции из `direction.dart`:
- `categoryIndex`: категория в двух направлениях достаётся первому по `order`;
- `ladder` / `nextOpen`: порядок, пропуск закрытых, null на пройденной лестнице;
- `closureRate`: 0 без закрытий; закрытия старше окна не считаются;
- `directionEta`: null без темпа и на пройденной лестнице; при темпе 1 веха /
  30 дней и трёх открытых вехах — примерно +90 дней;
- `pomosByDirection`: помидор с чужой категорией попадает в ключ `''`;
- `closuresByWeek`: группировка по id недели.

Новый файл `test/course_merge_test.dart` — слияние:
- направления и вехи объединяются по id, порядок победителя первым;
- запись, которой нет у победителя, дописывается в конец;
- похороненное направление не воскресает после слияния (delete-wins);
- `milestoneId` спринта берётся у победителя, но НЕ исчезает, если у
  победителя этого ключа нет вообще (та же ловушка, что была с `milestone`,
  смотри комментарий в `_mergeSprints`).

Стиль тестов — как в `test/data_merge_test.dart` и `test/planner_buckets_test.dart`.
Прочитай оба перед тем как писать.
</task>

<constraints>
- Не трогай `lib/presentation/**`, `lib/app/**`, `lib/services/**` — другая задача.
- Не трогай зеркала в валт (`_mirrorTasks`, `_mirrorAll`, `markdown_codec.dart`).
- Все 104 существующих теста обязаны остаться зелёными, особенно
  `test/data_merge_test.dart`, `test/sync_regressions_test.dart`,
  `test/json_data_repository_test.dart`.
- Ничего не переименовывай в существующем API.
- Новых пакетов в `pubspec.yaml` не добавлять.
- Комментарии по-русски и объясняют ПОЧЕМУ, а не пересказывают код.
- Код проходит `flutter analyze` начисто (строгий набор, см. `analysis_options.yaml`).
</constraints>

<done_when>
- `flutter analyze` — 0 issues;
- `flutter test` — всё зелёное, тестов стало минимум на 14 больше;
- старый `data.json` без ключей `dirs`/`miles` читается без ошибок и после
  записи ничего не теряет.
</done_when>
