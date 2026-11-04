# P05 — InsightCubit и проводка

Исполнитель: **Sonnet**. Зависит от: P02, P03, P04.

<role>
Прочитай `plan/tasks/P00-общее.md`, обзор §3 и §5. Код: `lib/main.dart` целиком,
`lib/presentation/cubits/sprint_cubit.dart` и `stats_cubit.dart` (образец состояния,
`status`-enum, `refresh`), `lib/presentation/cubits/activity_cubit.dart`
(`focusPercent`, `segmentsFor` — источник доли отвлечений), `lib/domain/insights.dart`,
`lib/domain/strategies.dart`, `test/screen_fakes.dart`.
</role>

<task>
## 1. `lib/presentation/cubits/insight_cubit.dart`

Конструктор: `InsightRepository`, `JournalRepository`, `SprintRepository`,
`AppSettings Function() settings`, `double? Function(DateTime from, DateTime to)? distractPercent`
(в main — из ActivityTracker; null на Android и в тестах).

Состояние (`InsightStatus { loading, ready, failure }`):
- `days` — `List<DayLog>` за последние 182 дня (`range`), включая сегодня;
- `sprint` — текущий спринт (`SprintRepository.current`), `previous` — прошлый
  (для вердикта; найди способ получить спринт прошлой недели через репозиторий —
  если метода нет, добавь `Future<Either<Failure, Sprint?>> sprintById(String id)` в
  `SprintRepository` и реализацию);
- `lastDeferral` — `({Episode episode, int count})?` — для снекбара P07.

Геттеры (вся арифметика — вызовы `insights.dart`/`strategies.dart`, не дублировать):
`today`, `todayEpisodes`, `checkIn`, `current`/`previousWeek`/`baselineInsight`
(`WeekInsight` по дням недели; `windows` из настроек через `parseSessionWindows`),
`stats` (за все 182 дня), `baselineWeekId`, `observation` (`isObservationWeek`),
`experiment` (из `sprint`), `ranked(Cause c)` (с pinned = способ эксперимента),
`pendingEpisode(EpisodeSource s)` — последний эпизод сегодня этого источника без
причины, созданный ≤ 60 мин назад (иначе null), `yesterday` — DayLog предыдущего
логического дня.

Команды (каждая: вызов репозитория → `refresh()`; ошибка → `failure` с сообщением,
как в `SprintCubit._save`):
- `Future<Episode> addEpisode({required EpisodeSource source, PomoTask? task, String app = '', Cause? cause, String thought = ''})` —
  `id: newId()`, `at: clock.now()`, снимок задачи (id, описание, категория);
- `setCause(String id, Cause c, {String thought = ''})`, `setStrategy(String id, StrategyKind k, {String fact = '', String alt = ''})`,
  `deleteEpisode(String id)`;
- `setCheckIn(CheckIn ck)` — на сегодняшний логический день;
- `saveIps(List<int> answers)`;
- `startExperiment(Experiment e)` → текущий спринт; `setVerdict(String sprintId, Verdict v)`; `clearExperiment()`;
- `saveReview(WeekReview r)`;
- `reportDeferral(Episode e, int count)` — только emit `lastDeferral` (P06 вызывает после addEpisode).

## 2. Проводка в `main.dart`

- Создать после `dataRepository`, передать `distractPercent` через `activityTracker.data`
  (функция пересечения: сумма `focusSegments` за период по отвлекающим ключам / все
  focus-секунды; используй существующий `segmentsSummary` и `distracting` из трекера;
  на не-Windows — `null`). Порядок создания: `activityTracker` сейчас создаётся ниже —
  перенеси его создание выше или передай замыкание, читающее его лениво.
- `insightCubit.refresh()` во всех местах, где сейчас подряд вызываются
  `statsCubit.refresh()`, `sprintCubit.refresh()`, `directionsCubit.refresh()`
  (`onPomodoroComplete`, `onDayChanged`, `reloadVault`, `onHistoryWritten`,
  `onJournalChanged`, `bootstrap`). Эти блоки уже повторяются 5 раз — сверни их в
  одну локальную функцию `refreshViews()` и вызывай её; поведение не меняй.
- `BlocProvider.value(value: insightCubit)`.
- Добавь фейк в `test/screen_fakes.dart` и провайдер в сборку дерева тестов.
</task>

<tests>
`test/insight_cubit_test.dart` с фейковыми репозиториями (по образцу
`directions_cubit_test.dart`): addEpisode → появился в `todayEpisodes`; `pendingEpisode`
не отдаёт эпизод с причиной и старше 60 мин (через `withClock`); `observation` true без
эпизодов; `ranked` ставит способ эксперимента первым; `setCheckIn` дважды сливает поля.
</tests>
