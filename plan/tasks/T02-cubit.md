<role>
Flutter-проект `C:\Users\PC\StudioProjects\pomodoro_tracker` (Flutter 3.44 /
Dart 3.12). Помидоро-таймер с задачником. Состояние — Cubit (`flutter_bloc`),
состояния на `Equatable`. Ошибки — `Either<Failure, T>` (fpdart) на границе
репозиториев. Все тексты интерфейса ТОЛЬКО в `lib/app/strings.dart` (два
языка, ru/en), цвета только в `lib/app/theme.dart`. Комментарии по-русски,
объясняют ПОЧЕМУ.

Задача T01 уже выполнена: существуют `lib/domain/entities/direction.dart`
(`Direction`, `Milestone`, `DirectionStatus`, чистые функции `categoryIndex`,
`ladder`, `nextOpen`, `closureRate`, `directionEta`, `pomosByDirection`,
`closuresByWeek`), интерфейс `DirectionRepository` с `loadCourse()` /
`saveCourse(Course)` в `lib/domain/repositories.dart` (`Course` — рекорд
`({List<Direction> directions, List<Milestone> milestones})`), и его
реализация в `JsonDataRepository`. Прочитай эти файлы перед началом.
</role>

<task>
Сделай слой состояния и тексты для «Курса» — направлений и лестниц вех.
Экранов в этой задаче НЕ рисуй, только cubit, строки и проводка.

## 1. `lib/presentation/cubits/directions_cubit.dart`

По образцу `lib/presentation/cubits/sprint_cubit.dart` (прочитай его — тот же
стиль состояния, `status`-enum, `refresh`, приватный `_save`).

    enum DirectionsStatus { loading, ready, failure }

    class DirectionsState extends Equatable {
      const DirectionsState({
        required this.status,
        this.directions = const [],
        this.milestones = const [],
        this.error = '',
      });
      ...
    }

Геттеры состояния (вся арифметика — вызовы чистых функций из
`direction.dart`, дублировать логику запрещено):
- `List<Direction> get active` — статус `active`, по `order`;
- `List<Direction> get paused`, `List<Direction> get finished`;
- `Milestone? next(String directionId)`;
- `({int done, int total}) progress(String directionId)`;
- `Milestone? milestoneById(String id)`;
- `Direction? directionOf(Milestone m)`;
- `Direction? directionForCategory(String category)` — через `categoryIndex`;
- `Map<String, List<Milestone>> get closuresByWeekMap`.

Команды (каждая пересобирает списки и зовёт `_save`, который пишет через
`DirectionRepository.saveCourse` и на ошибке эмитит `failure` с сообщением —
ровно как `SprintCubit._save`):
- `addDirection(String name)` — id через `newId()` из
  `lib/data/json_data_repository.dart`, `order` = max+1, статус `active`;
- `updateDirection(Direction d)`;
- `setStatus(String id, DirectionStatus status)`;
- `reorderDirections(int oldIndex, int newIndex)` — перенумеровать `order`
  подряд от 0 после перестановки;
- `deleteDirection(String id)` — вместе с его вехами;
- `addMilestone(String directionId, String title)` — `order` = max+1 внутри
  направления;
- `updateMilestone(Milestone m)`;
- `reorderMilestones(String directionId, int oldIndex, int newIndex)` —
  перенумеровать `order` подряд внутри направления;
- `deleteMilestone(String id)`;
- `closeMilestone(String id, String sprintId, DateTime at)` — ставит
  `doneSprint` и `doneAt`;
- `reopenMilestone(String id)` — через `copyWith(reopen: true)`.

Важно: `closeMilestone` и `reopenMilestone` НЕ трогают спринт — связку
`Sprint.milestoneId` двигает T04. Здесь только данные курса.

## 2. `lib/app/strings.dart`

Добавь новую секцию `// Курс` со всеми текстами ru/en в существующем стиле
(`static String get x => _t('ру', 'en');`, параметризованные — методами).
Минимальный набор (имена подбери в стиле файла, тексты — по смыслу):

- навигация: `navCourse` — «Курс» / «Course»;
- заголовки: «Направления», «На паузе», «Закрытые», «Лестница вех»,
  «Лента закрытий», «Внимание за 30 дней», «Месячный разбор»;
- пустые состояния: «Пока ни одного направления. Направление — это цель на
  3–12 месяцев; держи 2–4 активных, остальное — на паузу.»;
  «Лестница пуста. Веха — проверяемый результат на 1–3 недели, а не занятие:
  «бот отвечает на 3 команды в проде», а не «работать над ботом».»;
- кнопки/подсказки: «Направление», «Веха», «Добавить направление»,
  «Добавить веху», «Пауза», «Вернуть в работу», «Закрыть направление»,
  «Закрыть веху», «Открыть заново», «Категории», «Заметка в Obsidian»,
  «Горизонт», «Без горизонта»;
- предупреждение о перегрузе: `tooManyDirections(int n)` → «Активных
  направлений: N. Работает 2–4 — остальное лучше на паузу.»;
- прогресс лестницы: `ladderProgress(int done, int total)` → «веха N из M»;
- темп: `paceLabel(String value)` → «темп N вех/мес», `noPace` → «темпа пока
  нет», `etaLabel(String date)` → «при текущем темпе — к DATE»;
- нить в карточке «СЕЙЧАС»: разделитель ` → ` уже в коде, нужны только
  `courseThreadNoDirection` и т.п., если понадобятся;
- месячный разбор: `monthReviewTitle`, `monthReviewClosed(int n)` →
  «Закрыто вех за месяц: N», `monthReviewStale(String name, int weeks)` →
  «NAME не двигалось N недель — пауза или №1?», `monthReviewDismiss` → «Понял»;
- подтверждение удаления: `deleteDirectionConfirm(String name)` →
  «Удалить направление NAME вместе с его вехами?».

Проверь `test/strings_test.dart` — если он сверяет полноту ru/en, новые
строки обязаны его пройти.

## 3. Проводка в `lib/main.dart`

- Создай `directionsCubit = DirectionsCubit(dataRepository);` рядом с
  `sprintCubit`, вызови первичный `refresh()` там же, где обновляются
  остальные кубиты при старте (посмотри, как это сделано для `sprintCubit`).
- Добавь `BlocProvider.value(value: directionsCubit)` в `MultiBlocProvider`.
- Там, где после синка/rollover перечитываются данные (`applyRemote`,
  `rolloverCheck`, обработчик прихода удалённой версии), добавь
  `directionsCubit.refresh()` рядом с существующими обновлениями — иначе
  приехавшее с другого устройства направление не появится до перезапуска.

## 4. Тест

`test/directions_cubit_test.dart` — с фейковым `DirectionRepository`
в памяти (образец фейков: `test/screen_fakes.dart`, прочитай его):
- добавление направления и вехи, порядок `order`;
- `reorderMilestones` перенумеровывает подряд;
- `closeMilestone` → `nextOpen` отдаёт следующую;
- `deleteDirection` уносит и вехи направления;
- `progress` считает закрытые/всего.
</task>

<constraints>
- Экраны (`lib/presentation/screens/**`), `home_shell.dart` и виджеты
  НЕ трогай — это задачи T03/T04.
- Никаких хардкод-строк в коде вне `strings.dart`.
- Всю арифметику бери из чистых функций `direction.dart`, не дублируй.
- Существующие тесты обязаны остаться зелёными.
- Новых пакетов не добавлять.
- Комментарии по-русски, объясняют ПОЧЕМУ.
</constraints>

<done_when>
- `flutter analyze` — 0 issues;
- `flutter test` — всё зелёное, включая новый `test/directions_cubit_test.dart`;
- `DirectionsCubit` доступен через контекст в любом экране приложения.
</done_when>
