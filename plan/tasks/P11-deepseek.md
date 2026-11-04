# P11 — DeepSeek: настройки, сервис, три вызова

Исполнитель: **Opus** (промты, проверка ответа, ошибки сети). Зависит от: P07, P08, P10.

<role>
Прочитай `plan/tasks/P00-общее.md`, обзор §6 целиком (API проверено по докам DeepSeek
2026-11-04) и §1 п. 4 («без ИИ работает всё»). Код: `lib/core/failure.dart`,
`lib/services/notify_service.dart` (как сделан HTTP к Telegram — повтори стиль),
`lib/domain/entities/app_settings.dart`, `lib/presentation/screens/settings_dialog.dart`,
`lib/presentation/widgets/first_step_field.dart`, `episode_sheet.dart`,
`lib/presentation/screens/insight_screen.dart`, `lib/domain/insights.dart`,
`lib/domain/strategies.dart`. Тесты HTTP — через `package:http/testing.dart` (`MockClient`),
он входит в `http`, новых зависимостей не нужно.
</role>

<task>
## 1. Настройки

`AppSettings`: `aiEnabled` (false), `aiKey` (''), `aiModel` ('deepseek-flash'),
`aiConsent` (false). Новая вкладка «ИИ» / "AI" в `settings_dialog.dart` (5-я, после «Канбана»):
- `SwitchListTile` «Подсказки ИИ (DeepSeek)»;
- поле «API-ключ» — `obscureText` с кнопкой-глазом; под ним ссылка
  «Получить ключ» → `https://platform.deepseek.com/api_keys` (`url_launcher` уже есть);
- поле «Модель», подсказка «deepseek-flash = V4.1 Flash»;
- кнопка «Проверить» → `ai.ping()` → снекбар «Ключ работает» или текст ошибки;
- текст: «Уходит: текст задачи, мысли из листа эпизода, недельные цифры. Не уходит:
  окна, заметки, ключи других сервисов. Сервер DeepSeek — в Китае.»

## 2. `lib/core/failure.dart`

`final class AiFailure extends Failure` и `final class AiConcern extends Failure`
(модель вернула `concern: true`; `message` — `S.aiConcern`).

## 3. `lib/services/ai_service.dart`

```dart
class AiService {
  AiService(this._settings, {http.Client? client});
  bool get available;   // aiEnabled && aiKey.isNotEmpty
  Future<Either<Failure, Unit>> ping();
  Future<Either<Failure, List<String>>> firstSteps({required String task, String category = '',
      String direction = '', String milestone = '', Cause? cause, String thought = ''});
  Future<Either<Failure, Reframe>> reframe({required String thought, Cause? cause, String task = ''});
  Future<Either<Failure, AiReview>> weeklyReview(Map<String, Object?> payload);
}
typedef Reframe = ({String pattern, String question, String alternative});
typedef AiReview = ({WeekReview review, Experiment? experiment});
```

Запрос (`_chat(system, user, maxTokens)`):
```json
POST https://api.deepseek.com/chat/completions
Authorization: Bearer <aiKey>
{
  "model": "<aiModel>",
  "messages": [{"role":"system","content":"…"},{"role":"user","content":"<json входа>"}],
  "response_format": {"type": "json_object"},
  "thinking": {"type": "disabled"},
  "max_tokens": 300,
  "stream": false
}
```
- Таймаут 30 с. Ответ: `choices[0].message.content`.
- Пустой `content` → один повтор, снова пусто → `AiFailure(S.aiEmpty)`.
- HTTP: 401 → `S.aiBadKey` «Ключ не подходит»; 402 → `S.aiNoBalance` «На счёте DeepSeek
  нет денег»; 429 → `S.aiBusy` «Слишком много запросов, попробуй через минуту»;
  5xx/сеть/таймаут → `S.aiError` «DeepSeek не ответил».
- `ping()` — без `response_format`, сообщение `"ping"`, `max_tokens: 1`.
- `max_tokens`: firstSteps 300, reframe 300, weeklyReview 900.
- Язык: `S.lang == ru ? 'Russian' : 'English'` в системном промте.

Разбор ответа — чистые функции в том же файле (их и тестировать):
`parseFirstSteps(String raw)`, `parseReframe(String raw)`, `parseReview(String raw)`:
- не JSON / не те типы → `AiFailure(S.aiError)`;
- `concern == true` → `AiConcern`;
- строки обрезать: шаги 80, question 100, alternative 140, summary 400, pattern text 140,
  evidence 120, hypothesis 140; шагов ровно до 3, закономерностей до 3; пустые выбросить;
- `pattern` не из списка → `none`;
- `experiment.strategy` / `metric` не из `StrategyKind.values` / `InsightMetric.values`
  (сравнивать по `name`) → `experiment = null` (остальной разбор годится).

### Системные промты (дословно, `{language}` подставляется)

**firstSteps**
```
You help a person start a task they keep putting off. Suggest exactly 3 first steps.
Each step is one concrete physical action that takes under 5 minutes, starts with a verb,
is at most 80 characters, and is specific to THIS task (name the file, page, tool or person
when the task implies one). No advice, no motivation, no plan of the whole task.
If the input suggests a crisis or self-harm, set "concern" to true and return no steps.
Respond in {language}. Output only json, for example:
{"steps": ["Open the Stripe dashboard → Webhooks", "Copy the endpoint URL into .env", "Write one test request in curl"], "concern": false}
```
Вход (user, JSON): `{"task","category","direction","milestone","cause","thought"}`
(`cause` — `name` причины; пустые поля не отправлять).

**reframe**
```
You help a person check one unhelpful thought that stops them from starting a task,
using a cognitive-behavioral approach. You are not a therapist and you do not diagnose.
Pick the closest thinking pattern from: all_or_nothing, catastrophizing, should,
mind_reading, discounting, overgeneralizing, none.
Write one short Socratic question (max 100 characters) that tests the thought against facts,
and one balanced alternative thought in the first person (max 140 characters) — realistic,
not cheerful.
If the text suggests a crisis or self-harm, set "concern" to true and leave the other fields empty.
Respond in {language}. Output only json, for example:
{"pattern": "all_or_nothing", "question": "What would a good-enough first version look like?", "alternative": "A rough first version is a normal step; I can improve it tomorrow.", "concern": false}
```
Вход: `{"thought","cause","task"}`.

**weeklyReview**
```
You analyse one week of a person's self-tracking about procrastination. The data is
aggregated; "baseline" is their first observation week. Numbers are small and noisy:
state a pattern only when the data shows it, and quote the numbers as evidence.
No diagnoses, no praise, no moralizing.
Return:
- "summary": 2–3 sentences about the week;
- "patterns": up to 3 items {"text", "evidence"};
- "experiment" for next week: "strategy" strictly one of [{strategies}], "metric" strictly
  one of [{metrics}], "hypothesis" in the form "If …, then …" (max 140 characters).
  Prefer the strategy that worked best for the most frequent cause. If last week's
  experiment has verdict "works", you may keep it.
If the notes suggest a crisis or self-harm, set "concern" to true.
Respond in {language}. Output only json, for example:
{"summary": "…", "patterns": [{"text": "…", "evidence": "…"}], "experiment": {"strategy": "firstStep", "metric": "firstStart", "hypothesis": "If my frog has a first step, then I start it earlier"}, "concern": false}
```
`{strategies}` / `{metrics}` — `name` всех значений enum через запятую.

### Вход недельного разбора

Чистая функция `Map<String, Object?> reviewPayload(InsightState s)` в
`lib/domain/insights.dart` или рядом с кубитом: неделя, `observation`, метрики
`current/previous/baseline` (`metric.name → value`), причины (`cause.name → count`),
способы (`kind.name → {tries, wins}`), разбиения самочувствия, эксперимент
(гипотеза, способ, метрика, было, сейчас, вердикт), до 20 последних мыслей недели
(`thought`, обрезка 120). **Не включать** имена окон (`app`), заметки дня, описания задач.

## 4. Подключение

- `main.dart`: `final ai = AiService(settings);` — передать через
  `RepositoryProvider.value` (или аргументом в виджеты — как проще в этом проекте).
- **Согласие:** первый вызов любого метода при `aiConsent == false` → диалог
  «Текст задачи и мысли уйдут в DeepSeek (Китай). Продолжить?» [Отмена] [Да, не спрашивать] →
  `aiConsent = true`. Общая функция `Future<bool> ensureAiConsent(BuildContext)`.
- **`FirstStepField`**: если `ai.available` — в `trailing` иконка ✨ (`Icons.auto_awesome`,
  tooltip «Подсказать первый шаг»). Нажатие → индикатор в кнопке → под полем 3
  `ActionChip`, тап заполняет поле. `AiConcern` → вместо чипов текст `S.aiConcern`
  (без кнопок). Ошибка → снекбар с сообщением. Полю нужны данные задачи — добавь
  параметры `task`, `category`, `cause`, `thought` (необязательные).
- **Способ «Проверить мысль»**: ✨ рядом с полем «Как сказать точнее» → `reframe` →
  заполнить поле `alternative`, над полем подпись «Похоже на: {pattern}» (`S.thinkingPattern`)
  и вопрос `question` серым. `pattern == none` → только вопрос.
- **Разбор → слот ИИ**: кнопка «✨ Разбор от ИИ» (если `available`), повторное нажатие —
  «Обновить». Ответ → `insight.saveReview(review)` (кеш в спринте + зеркало), а
  `experiment` (если есть и текущего эксперимента нет) заменяет правило в
  карточке-предложении. Есть сохранённый разбор — показать его, вызов не делать.

`S.aiConcern` — «Похоже, сейчас тяжело не с задачей. Об этом стоит поговорить с
близким человеком или специалистом.» / "It sounds like this is about more than the task.
It's worth talking to someone close to you or a professional."
Подписи паттернов `S.thinkingPatternName(id)`: «всё или ничего», «катастрофизация»,
«долженствование», «чтение мыслей», «обесценивание», «сверхобобщение».
</task>

<tests>
`test/ai_service_test.dart` (`MockClient`): тело запроса содержит model, `json_object`,
`thinking disabled`, `max_tokens`, заголовок Bearer; пустой content → ровно 2 запроса;
401/402/429/500 → нужные сообщения; `concern: true` → `AiConcern`; разбор режет длины,
выбрасывает 4-й шаг, неизвестный pattern → none, неизвестный strategy → experiment null;
`reviewPayload` не содержит `app` и описаний задач (проверить по всем строкам JSON).
Виджеты: ✨ нет при `available == false`; при согласии false показывается диалог.
</tests>

**Решение при реализации:** `AiService` получил необязательный `onConsent` (main пишет `aiConsent = true` через `SettingsCubit`), поэтому `ensureAiConsent(context, ai)` принимает сервис вторым аргументом — диалоговые маршруты в тестах не видят провайдеров экрана. Сервис лежит в дереве как `RepositoryProvider.value`; `aiOf(context)` ищет nullable-тип и без провайдера даёт null — ✨ тогда просто нет (так же в старых тестах). `showEpisodeSheet` и `showTaskEditDialog` резолвят сервис до открытия и передают явно. Сервис сам отказывает без ключа/включения/согласия (запроса нет); `ping()` требует только ключ и согласие — ключ проверяют до включения. 400/404/422 → `S.aiRejected` («проверь модель»), остальные коды — как в задаче. Ответ читается из `bodyBytes` как UTF-8 (без charset `http` берёт latin1). Пустой content (и `null`) → ровно один повтор. Обрезка — по runes с схлопыванием пробелов; в шагах не-строки и пустые выбрасываются, пустой итог — ошибка; у reframe ошибка, если пусты и вопрос, и альтернатива; `concern` — `true` или `"true"`. `reviewPayload(...)` — чистая функция в `insights.dart` с явными аргументами (недели считаются в кубите, нужны окна и трекер), обёртка `InsightCubit.aiPayload()`; блоки `current`/`previous` (метрики, причины, способы, activeDays, эпизоды), `baseline.metrics`, `wellbeing` (сон/энергия × простой/🐸 за 4 недели), `experiment` — прошлой недели с вердиктом (сохранённый или расчётный), `currentExperiment`, до 20 мыслей за текущую и прошлую неделю (разбор делают в понедельник). Задачи, категории, `app`, `fact`/`alt`, заметки не уходят. Эксперимент ИИ в `WeekReview` не хранится (поля нет): живёт в состоянии вкладки «Неделя» для своей недели, `baseline` подставляет экран (прошлая неделя, иначе база); метрика `distract` без трекера отбрасывается. `aiSlot` по-прежнему перекрывает слот целиком. `FirstStepField` стал Stateful (поле + чипы под ним), ✨ только при непустом `task`; в редакторе задачи он перестраивается от описания/категории через `ListenableBuilder`. В листе эпизода «Как сказать точнее» — свой `_AltField` с контроллером; ✨ появляется, когда мысль непуста. Тест вкладки «ИИ» в настройках не добавлялся (диалог тянет почти все кубиты, как в P09).
