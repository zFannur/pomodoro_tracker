// Содержимое справки. Чистый Dart (без Flutter): его читает и окно помощи,
// и тест-генератор docs/КАК-ПОЛЬЗОВАТЬСЯ.md. Источник текста —
// plan/help/СПРАВКА.md; в строках понимаются только **жирный** и `код`.
import '../domain/entities/app_settings.dart' show AppLanguage;
import 'strings.dart';

/// Куда ведёт кнопка «Открыть…» и шаг пути внедрения.
enum HelpTarget {
  timer,
  tasks,
  sprint,
  course,
  stats,
  review,
  reviewEpisodes,
  reviewWindows,
  settingsTimer,
  settingsNotify,
  settingsApp,
  settingsAi,
}

sealed class HelpBlock {
  const HelpBlock();
}

final class Lead extends HelpBlock {
  const Lead(this.text);
  final String text;
}

final class Para extends HelpBlock {
  const Para(this.text);
  final String text;
}

final class Heading extends HelpBlock {
  const Heading(this.text);
  final String text;
}

final class Steps extends HelpBlock {
  const Steps(this.items);
  final List<({String where, String what})> items;
}

/// Текст идёт сразу после термина как есть: тире, если оно нужно, — в начале
/// текста. Термин может быть пустым.
final class Bullets extends HelpBlock {
  const Bullets(this.items);
  final List<({String term, String text})> items;
}

final class Compare extends HelpBlock {
  const Compare(this.items);
  final List<({String bad, String good})> items;
}

final class Tip extends HelpBlock {
  const Tip(this.text);
  final String text;
}

final class Warn extends HelpBlock {
  const Warn(this.text);
  final String text;
}

final class Go extends HelpBlock {
  const Go(this.label, this.target);
  final String label;
  final HelpTarget target;
}

/// Интерактивный путь внедрения (этапы из [adoptionStages]).
final class PathBlock extends HelpBlock {
  const PathBlock();
}

/// Список ссылок из [helpSources].
final class Sources extends HelpBlock {
  const Sources();
}

class HelpSection {
  const HelpSection(this.id, this.emoji, this.title, this.blocks);
  final String id;
  final String emoji;
  final String title;
  final List<HelpBlock> blocks;
}

class HelpStage {
  const HelpStage(this.title, this.hint, this.steps);
  final String title;

  /// Строка под заголовком этапа.
  final String hint;
  final List<HelpStep> steps;
}

class HelpStep {
  const HelpStep(
    this.id,
    this.title,
    this.where,
    this.rule,
    this.target, {
    this.optional = false,
    this.windowsOnly = false,
  });
  final String id;
  final String title;

  /// «Курс → ⋮ → Категории»; «—», если у шага нет места.
  final String where;

  /// Как шаг отмечается («сам: …» или «вручную») — только для документа.
  final String rule;
  final bool optional;
  final bool windowsOnly;
  final HelpTarget? target;
}

String _t(String ru, String en) => S.lang == AppLanguage.ru ? ru : en;

List<HelpSection> helpSections() =>
    S.lang == AppLanguage.ru ? _ru : _en;

List<HelpStage> adoptionStages() =>
    S.lang == AppLanguage.ru ? _stagesRu : _stagesEn;

List<({String title, String url})> helpSources() =>
    S.lang == AppLanguage.ru ? _sourcesRu : _sourcesEn;

/// Без разметки `**` и `` ` ``: по такому тексту ищет справка.
String plainText(String s) => s.replaceAll('**', '').replaceAll('`', '');

/// Все строки раздела, по которым ищет поиск. У раздела с путём — ещё
/// заголовки этапов и шагов и их «где».
List<String> sectionTexts(HelpSection s) => [
  s.title,
  for (final b in s.blocks) ...switch (b) {
    Lead(:final text) ||
    Para(:final text) ||
    Heading(:final text) ||
    Tip(:final text) ||
    Warn(:final text) => [text],
    Steps(:final items) => [
      for (final i in items) ...[i.where, i.what],
    ],
    Bullets(:final items) => [
      for (final i in items) ...[i.term, i.text],
    ],
    Compare(:final items) => [
      for (final i in items) ...[i.bad, i.good],
    ],
    Go(:final label) => [label],
    PathBlock() => [
      for (final st in adoptionStages()) ...[
        st.title,
        st.hint,
        for (final step in st.steps) ...[step.title, step.where],
      ],
    ],
    Sources() => [for (final src in helpSources()) src.title],
  },
].map(plainText).where((t) => t.isNotEmpty).toList();

/// Раздел подходит под запрос: вхождение без учёта регистра.
bool sectionMatches(HelpSection s, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return sectionTexts(s).any((t) => t.toLowerCase().contains(q));
}

/// Markdown для docs/КАК-ПОЛЬЗОВАТЬСЯ.md — тот же текст, что в окне помощи.
String helpMarkdown() {
  final out = StringBuffer()
    ..writeln('# ${_t('Как пользоваться', 'How to use')}')
    ..writeln()
    ..writeln(
      _t(
        '> Сгенерировано из справки приложения — правь '
            '`lib/app/help_content.dart`, затем '
            '`UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart`.',
        '> Generated from the in-app help — edit '
            '`lib/app/help_content.dart`, then run '
            '`UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart`.',
      ),
    );
  for (final s in helpSections()) {
    out
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## ${s.emoji} ${s.title}');
    for (final b in s.blocks) {
      final text = _blockMarkdown(b);
      if (text.isEmpty) continue;
      out
        ..writeln()
        ..writeln(text);
    }
  }
  return out.toString();
}

String _blockMarkdown(HelpBlock b) => switch (b) {
  Lead(:final text) => '> $text',
  Para(:final text) => text,
  Heading(:final text) => '### $text',
  Steps(:final items) => [
    for (var i = 0; i < items.length; i++)
      '${i + 1}. **${items[i].where}** — ${items[i].what}',
  ].join('\n'),
  Bullets(:final items) => [
    for (final i in items)
      i.term.isEmpty ? '- ${i.text}' : '- **${i.term}** ${i.text}',
  ].join('\n'),
  Compare(:final items) => [
    for (final i in items) '- ✗ ${i.bad} ⇒ ✓ ${i.good}',
  ].join('\n'),
  Tip(:final text) => '> 💡 $text',
  Warn(:final text) => '> ⚠️ $text',
  // Кнопка перехода живёт только в окне приложения.
  Go() => '',
  PathBlock() => _pathMarkdown(),
  Sources() => [
    for (final s in helpSources()) '- [${s.title}](${s.url})',
  ].join('\n'),
};

String _pathMarkdown() {
  final out = StringBuffer(
    _t(
      'Этап считается пройденным, когда отмечены все его обязательные шаги; '
          'необязательные («по желанию») этап не держат. В приложении '
          'галочки ставятся сами — по данным; руками отмечаются только шаги '
          '«вручную».',
      'A stage is complete when all its required steps are checked; optional '
          'ones do not hold it back. In the app the checks appear on their '
          'own, from your data; only the "manual" steps are checked by hand.',
    ),
  );
  final stages = adoptionStages();
  for (var i = 0; i < stages.length; i++) {
    final st = stages[i];
    out
      ..writeln()
      ..writeln()
      ..writeln('### ${_t('Этап', 'Stage')} ${i + 1}. ${st.title}')
      ..writeln()
      ..writeln(st.hint)
      ..writeln()
      ..writeln(
        '| ${_t('Шаг', 'Step')} | ${_t('Где', 'Where')} | '
        '${_t('Отмечается', 'Checked')} |',
      )
      ..write('|---|---|---|');
    for (final step in st.steps) {
      final tags = [
        if (step.optional) _t('по желанию', 'optional'),
        if (step.windowsOnly) 'Windows',
      ];
      out
        ..writeln()
        ..write(
          '| ${step.title}${tags.isEmpty ? '' : ' *(${tags.join(', ')})*'} '
          '| ${step.where} | ${step.rule} |',
        );
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Русский текст (дословно из plan/help/СПРАВКА.md)
// ---------------------------------------------------------------------------

const _ru = <HelpSection>[
  HelpSection('start', '🚀', 'С чего начать', [
    Lead(
      'Это не только таймер. Здесь три слоя: план (что важно), исполнение '
      '(помидоры) и самонаблюдение (что мешает и что помогает). Внедряй по '
      'этапам: этап — примерно неделя.',
    ),
    PathBlock(),
    Tip(
      'Галочки ставятся сами, когда в данных появляется нужное. Руками '
      'отмечаешь только то, что приложение увидеть не может.',
    ),
  ]),
  HelpSection('levels', '🧭', 'Как устроено', [
    Lead(
      'Четыре уровня, каждый в 5–10 раз больше нижнего. Поэтому у направления '
      'получается 6–12 вех — список, который влезает на экран.',
    ),
    Steps([
      (
        where: 'Направление',
        what: '3–12 месяцев. Активных 2–4, остальные на паузе.',
      ),
      (
        where: 'Веха',
        what:
            '1–3 недели. Результат, который проверяется ответом «да» или «нет».',
      ),
      (
        where: '⭐ Задача спринта',
        what: 'дни. Обязательство недели, двигает веху.',
      ),
      (where: '🍅 Помидор', what: '25 минут. Единица работы.'),
    ]),
    Heading('Категория — это проект'),
    Para(
      'Направление держит список категорий. Всё, что сделано в этих '
      'категориях, засчитывается ему само — включая прошлую историю. '
      'Привязывать задачи к направлению руками не нужно.',
    ),
    Heading('«Зачем» у направления'),
    Para(
      'В меню ⋮ направления есть пункт «Зачем»: одна строка о том, что '
      'изменится в жизни, когда направление сделано. Она видна на карточке '
      'и в `Курс.md`, а способ «Зачем это мне» показывает её, когда задача '
      'кажется бессмысленной.',
    ),
    Heading('Корзины — это сроки, спринт — это ⭐'),
    Para(
      'Входящие, Завтра, Эта неделя, Позже — когда делать. Спринт — только '
      'задачи с ⭐. Задача может лежать во «Входящих» и при этом быть в '
      'спринте.',
    ),
    Heading('«Сегодня»'),
    Bullets([
      (term: 'СЕЙЧАС', text: '— верхняя задача списка. В работе всегда одна.'),
      (
        term: '🐸 Лягушка',
        text: '— самая неприятная задача дня, идёт первой. Снимается в 05:00.',
      ),
      (
        term: 'Сутки',
        text: 'идут с 05:00 до 05:00: помидор в 00:30 — это ещё вчера.',
      ),
    ]),
    Go('Открыть Курс', HelpTarget.course),
  ]),
  HelpSection('day', '☀️', 'Один день', [
    Heading('Утро — 2 минуты'),
    Steps([
      (
        where: 'Таймер → Карточка дня',
        what: 'отметь сон и энергию. Два тапа.',
      ),
      (
        where: 'Задачи',
        what: 'собери «Сегодня»: 🐸 и ещё две задачи. Не больше.',
      ),
      (
        where: 'Задачи',
        what:
            'поставь 🐸 на самую неприятную. Открой её и заполни «Первый шаг» '
            'в «Плане старта».',
      ),
      (where: 'Таймер', what: 'проверь карточку СЕЙЧАС и нажми Space.'),
    ]),
    Heading('Работа'),
    Bullets([
      (term: 'Одна задача.', text: 'Работает верхняя. Остальные ждут.'),
      (
        term: 'Мысль или новое дело',
        text:
            '— `Ctrl+N`, `Enter`: улетает во «Входящие», день не разрушается.',
      ),
      (
        term: 'Не идёт',
        text:
            '— кнопка «Не идёт» рядом со Стартом или чип «Застрял?». Одна '
            'причина, один способ.',
      ),
      (
        term: 'Не хочется начинать',
        text: '— разгон 10 минут. После него можно честно остановиться.',
      ),
      (
        term: 'Остановил помидор',
        text:
            '— «На чём встал?» одной строкой. Остановился не потому, что '
            'доделал, — отметь причину.',
      ),
    ]),
    Heading('Вечер — 5 секунд'),
    Para('Карточка дня: «Как прошёл день?». Это всё.'),
    Tip(
      'Ручного ввода за день — меньше минуты. Задержки, переносы и '
      'отвлечения приложение считает само.',
    ),
    Go('Открыть Таймер', HelpTarget.timer),
  ]),
  HelpSection('week', '📅', 'Неделя и месяц', [
    Heading('Понедельник — 10 минут'),
    Steps([
      (
        where: 'Разбор → Неделя',
        what: 'посмотри плитки и частые причины.',
      ),
      (
        where: 'Разбор → Эксперимент',
        what:
            'вынеси вердикт прошлой неделе. Автоматический вердикт можно '
            'поправить.',
      ),
      (
        where: 'Разбор → Эксперимент',
        what: 'возьми новый: предложенный или свой.',
      ),
      (
        where: 'Спринт',
        what:
            '«Взять следующую ступень»: веха недели подставится из лестницы.',
      ),
      (
        where: 'Задачи',
        what: 'поставь ⭐ на 2–3 задачи, которые двигают эту ступень.',
      ),
    ]),
    Heading('Когда ступень готова'),
    Para(
      'Спринт → «Закрыть веху». Следующая подставится сама, а закрытие '
      'навсегда останется в ленте на Курсе. Незакрытая ступень не сгорает — '
      'в понедельник берёшь её снова.',
    ),
    Heading('Раз в месяц — 10 минут'),
    Steps([
      (
        where: 'Курс',
        what:
            'баннер месячного разбора. По каждому застрявшему направлению: '
            '«На паузу» или «Сделать №1».',
      ),
      (
        where: 'Разбор',
        what:
            'шкала откладывания, 9 вопросов. Карточка появляется в первую '
            'неделю месяца.',
      ),
    ]),
    Go('Открыть Разбор', HelpTarget.review),
  ]),
  HelpSection('stuck', '🧱', 'Когда не идёт', [
    Lead(
      'Откладывание — не лень и не черта характера. Это способ ненадолго уйти '
      'от неприятного чувства, которое вызывает задача. Помогает не '
      '«соберись», а понять, что за чувство, и сделать вход в задачу меньше.',
    ),
    Heading('Сигналы — приложение ловит само'),
    Bullets([
      (
        term: 'Простой',
        text:
            '— таймер стоит 10 минут, а задачи есть: появляется чип '
            '«Застрял?». На Windows через 15 минут — одно уведомление, если '
            'ты за компьютером.',
      ),
      (
        term: 'Отвлечение',
        text:
            '— отмеченное окно открыто минуту подряд во время помидора: '
            'уведомление и чип.',
      ),
      (
        term: 'Перенос',
        text:
            '— отложил задачу, у которой уже наступил срок. С третьего раза '
            '— значок ↻3.',
      ),
      (
        term: '🐸 не тронута',
        text:
            '— за день по лягушке не было ни одного помидора: утром об этом '
            'скажет Карточка дня.',
      ),
      (term: 'Ранний стоп', text: '— причина в окне «На чём встал?».'),
      (term: 'Сам понял', text: '— кнопка «Не идёт».'),
    ]),
    Para('Отвечать не обязательно. Сигнал без ответа тоже попадает в разбор.'),
    Heading('Лист эпизода — три шага'),
    Steps([
      (where: 'Причина', what: 'один тап. Мысль — по желанию, одной строкой.'),
      (
        where: 'Способ',
        what:
            'первым стоит тот, что лучше всего помогал именно тебе. Не '
            'подходит — «Другой способ».',
      ),
      (
        where: 'Действие',
        what: 'кнопка сохраняет и запускает таймер. Лист закрывается.',
      ),
    ]),
    Heading('Семь причин'),
    Bullets([
      (
        term: 'Непонятно, с чего начать',
        text: '— задача размыта, у неё нет первого действия.',
      ),
      (term: 'Слишком большая', text: '— не видно конца, страшно браться.'),
      (term: 'Скучно', text: '— нет интереса и быстрой награды.'),
      (term: 'Боюсь сделать плохо', text: '— перфекционизм, страх оценки.'),
      (term: 'Нет сил', text: '— дело в состоянии, а не в задаче.'),
      (
        term: 'Не вижу смысла',
        text: '— задача не связана с тем, что для тебя важно.',
      ),
      (
        term: 'Отвлекли',
        text: '— помеха снаружи. Это не откладывание, но тоже считается.',
      ),
    ]),
    Heading('Девять способов'),
    Bullets([
      (
        term: 'Первый шаг на 5 минут',
        text:
            '— когда непонятно или слишком большое. Запиши самое первое '
            'физическое действие. Не решение — только вход.',
      ),
      (
        term: 'Только 10 минут',
        text:
            '— когда скучно или нет сил. Разгон 10 минут, после можно '
            'остановиться. Обычно не хочется.',
      ),
      (
        term: 'План «если — то»',
        text:
            '— «Когда ___, я ___». Работает при повторении, поэтому план '
            'показывается утром и в СЕЙЧАС.',
      ),
      (
        term: 'Уменьшить задачу',
        text:
            '— самая маленькая версия, которая ещё считается шагом вперёд. Её '
            '— первой.',
      ),
      (
        term: 'Проверить мысль',
        text:
            '— мысль — это гипотеза, а не факт. Что ты знаешь наверняка? Как '
            'сказать точнее?',
      ),
      (
        term: 'Взять чувство с собой',
        text: '— «Я замечаю мысль, что…». Не ждать, пока станет не страшно.',
      ),
      (
        term: 'Зачем это мне',
        text:
            '— вспомни «зачем» направления. Задача не про твои цели — ей '
            'место во «Входящих».',
      ),
      (
        term: 'Честный отдых',
        text: '— 10 минут без экрана: вода, окно, пройтись. Потом разгон.',
      ),
      (
        term: 'Убрать раздражитель',
        text:
            '— закрой вкладку, убери телефон, мысль, которая отвлекла, — во '
            '«Входящие».',
      ),
    ]),
    Warn(
      'Первая неделя — неделя наблюдения. Способы не предлагаются (кроме '
      '«Всё равно помочь»): без неё потом не с чем сравнивать.',
    ),
  ]),
  HelpSection('review', '🔍', 'Разбор и эксперименты', [
    Heading('Плитки недели'),
    Bullets([
      (
        term: 'Первый помидор',
        text:
            '— опоздание к первому окну сессии; без расписания — время '
            'первого помидора. Меньше — лучше.',
      ),
      (
        term: 'Простой',
        text: '— среднее время между помидорами. Меньше — лучше.',
      ),
      (
        term: '🐸 первой',
        text: '— в скольких днях лягушка была первым помидором.',
      ),
      (
        term: 'Переносы',
        text: '— сколько раз откладывал задачи, у которых наступил срок.',
      ),
      (
        term: 'Отвлечения',
        text: '— доля времени помидоров в отмеченных окнах. Только Windows.',
      ),
    ]),
    Para(
      'Стрелка — сравнение с прошлой неделей, «база» — с неделей наблюдения. '
      '«—» значит «мало данных», а не ноль.',
    ),
    Heading('Эксперимент недели'),
    Para(
      'Одна гипотеза на неделю, например «Если у 🐸 есть первый шаг, я '
      'начинаю раньше». Метрика считается сама. В конце недели вердикт: '
      'лучше на 15% — «работает», хуже на 15% — «хуже», иначе «без '
      'разницы». Меньше трёх дней данных — «мало данных».',
    ),
    Para('Работающий способ сам встаёт первым в листе эпизода.'),
    Tip(
      'Неделя — это мало. «Без разницы» — повод повторить эксперимент ещё '
      'неделю, а не бросать его.',
    ),
    Heading('Самочувствие и дела'),
    Para(
      'Связь сна и энергии с простоем и 🐸 появляется, когда и в хороших, и в '
      'плохих днях набирается хотя бы по три дня. Это наблюдение, а не '
      'доказательство.',
    ),
    Heading('Шкала откладывания'),
    Para(
      '9 вопросов раз в месяц. Метрики показывают поведение, шкала — как ты '
      'сам его ощущаешь. Меньше балл — меньше откладывания.',
    ),
    Go('Открыть Разбор', HelpTarget.review),
  ]),
  HelpSection('windows', '🪟', 'Окна и отвлечения', [
    Lead(
      'Только Windows. Трекер раз в 5 секунд записывает активное окно. '
      'Данные лежат только на этом компьютере: в синхронизацию и в ИИ не '
      'уходят; окна во время помидоров хранятся 60 дней, вне помидоров — 14.',
    ),
    Heading('Где смотреть'),
    Bullets([
      (
        term: 'Разбор → Окна',
        text: '— весь день: приложения, вкладки, доля отвлечений.',
      ),
      (
        term: 'Задача → ⋮ → «Окна задачи»',
        text: '— что было открыто во всех помидорах этой задачи.',
      ),
      (term: 'Сделано → ⋮ → «Что было открыто»', text: '— один помидор.'),
      (
        term: 'Разбор → Эпизоды → «Что было вместо»',
        text: '— чем был занят простой перед стартом.',
      ),
    ]),
    Heading('Отметь отвлечения'),
    Para(
      'Флажок у YouTube, соцсетей, мессенджеров — прямо в списке окон. От '
      'отметок зависят сигнал отвлечения, плитка «Отвлечения» и красные '
      'строки.',
    ),
    Tip(
      'Рабочий браузер целиком не отмечай: отмечаются отдельные вкладки по '
      'заголовку.',
    ),
    Go('Открыть окна', HelpTarget.reviewWindows),
  ]),
  HelpSection('ai', '✨', 'ИИ-подсказки', [
    Lead(
      'ИИ (DeepSeek V4.1 Flash) не разговаривает с тобой. Он дополняет три '
      'места: первые шаги для задачи, подсказку к мысли и разбор недели. Без '
      'ключа всё работает на правилах.',
    ),
    Heading('Подключить'),
    Steps([
      (
        where: 'platform.deepseek.com',
        what:
            'создай API-ключ и пополни баланс. Разбор недели стоит около '
            'десятой доли цента.',
      ),
      (
        where: 'Настройки → ИИ',
        what: 'включи, вставь ключ, нажми «Проверить».',
      ),
    ]),
    Heading('Что уходит в DeepSeek'),
    Bullets([
      (
        term: 'Уходит:',
        text:
            'текст задачи, её категория и направление, мысль из листа '
            'эпизода, недельные цифры.',
      ),
      (term: 'Не уходит:', text: 'окна, заметки «на чём встал», ключи и токены.'),
    ]),
    Para(
      'Сервер DeepSeek — в Китае. Ключ хранится только на этом устройстве; на '
      'телефоне его вводят отдельно.',
    ),
    Warn(
      'ИИ — не психолог и не ставит диагнозов. Если в тексте видно, что '
      'тяжело не с задачей, приложение вместо подсказки предложит поговорить '
      'с близким или специалистом.',
    ),
    Go('Настройки ИИ', HelpTarget.settingsAi),
  ]),
  HelpSection('words', '✍️', 'Как формулировать', [
    Heading('Веха — проверяется «да / нет»'),
    Compare([
      (bad: 'Работать над ботом', good: 'Бот отвечает на 3 команды в проде'),
      (
        bad: 'Разобраться с оплатой',
        good: 'Первый платёж прошёл от живого юзера',
      ),
      (
        bad: 'Подтянуть английский',
        good: 'Прошёл собеседование на английском',
      ),
    ]),
    Heading('Задача — можно начать за 5 минут'),
    Compare([
      (bad: 'Сделать оплату', good: 'Подключить Stripe webhook'),
      (bad: 'Написать статью', good: 'Набросать план статьи из 5 пунктов'),
    ]),
    Heading('Первый шаг — физическое действие'),
    Compare([
      (bad: 'Разобраться с API', good: 'Открыть доку API → раздел Auth'),
      (bad: 'Начать отчёт', good: 'Создать файл и написать заголовок'),
    ]),
    Heading('«Если — то» — конкретная ситуация'),
    Compare([
      (
        bad: 'Утром займусь',
        good: 'Когда сяду после завтрака, открою api.dart',
      ),
      (
        bad: 'Когда будет время',
        good: 'В 14:00 после обеда — первый шаг 🐸',
      ),
    ]),
    Para(
      'Слева — занятия, они не кончаются. Справа — действия и результаты, они '
      'закрываются.',
    ),
  ]),
  HelpSection('mistakes', '⚠️', 'Частые ошибки', [
    Bullets([
      (
        term: 'Пять активных направлений.',
        text: 'Не работает. Два-три, остальные на паузу.',
      ),
      (
        term: 'Веха на квартал.',
        text: 'Слишком крупно — движения не видно. Ступень — 1–3 недели.',
      ),
      (
        term: 'Лестница как задачник.',
        text: 'Ступень — результат. Дела живут в задачах с ⭐.',
      ),
      (
        term: 'Восемь задач на день.',
        text: 'Это список желаний, а не план. 🐸 и ещё две.',
      ),
      (
        term: 'Направление без категорий.',
        text: 'Внимание к нему не считается.',
      ),
      (
        term: 'Пропустить неделю наблюдения.',
        text: 'Потом не с чем сравнивать.',
      ),
      (
        term: 'Три эксперимента сразу.',
        text: 'Непонятно, что сработало. Один в неделю.',
      ),
      (
        term: 'Ругать себя за пустой день.',
        text:
            'Серии дней здесь нет намеренно: вчерашний день — данные, а не '
            'приговор.',
      ),
    ]),
  ]),
  HelpSection('keys', '⌨️', 'Клавиши и ввод', [
    Steps([
      (where: 'Space', what: 'старт / пауза.'),
      (where: 'Esc Esc', what: 'стоп (второе нажатие в течение 1,5 с).'),
      (where: 'Ctrl+N', what: 'добавить задачу из любого места.'),
      (where: '+ / −', what: 'помидоры первой задачи, с Shift — по 4.'),
      (where: 'F1', what: 'эта справка.'),
    ]),
    Heading('Умный ввод'),
    Para(
      '`#категория Описание ~3` — категория, описание и 3 помидора. `Enter` — '
      'во «Входящие», `Ctrl+Enter` — в «Сегодня». Клик по числу помидоров: '
      '+1, с Alt — −1, с Shift — ×4.',
    ),
  ]),
  HelpSection('science', '📚', 'Почему так', [
    Lead(
      'Приёмы взяты из подходов, которые проверяли в исследованиях. Это '
      'инструменты самонаблюдения, а не лечение.',
    ),
    Bullets([
      (
        term: 'КПТ',
        text:
            'снижает откладывание сильнее других подходов (метаанализ 24 '
            'исследований). В интернет-программе эффект был и без '
            'сопровождения специалиста.',
      ),
      (
        term: 'Планы «если — то»',
        text:
            'помогают тем сильнее, чем конкретнее ситуация и чем чаще план '
            'повторяешь (642 теста).',
      ),
      (
        term: 'ACT',
        text:
            '— не ждать, пока исчезнет неприятное чувство, а действовать ради '
            'того, что важно (53 исследования онлайн-программ).',
      ),
      (
        term: 'Поведенческая активация',
        text: '— действие раньше мотивации.',
      ),
      (
        term: 'Самопрощение',
        text:
            'после откладывания снижает откладывание в следующий раз.',
      ),
      (
        term: 'Цикл «наблюдение → причина → способ → рефлексия»',
        text: 'внутри планировщика проверяли с чат-ботом Moa.',
      ),
    ]),
    Sources(),
    Warn(
      'Если подавленность, тревога или бессонница держатся неделями — это '
      'повод поговорить со специалистом, а не перенастроить приложение.',
    ),
  ]),
];

const _stagesRu = <HelpStage>[
  HelpStage(
    'Настройка',
    'Один раз, 15 минут. Без направлений и категорий разбор не знает, куда '
    'уходит внимание.',
    [
      HelpStep(
        'setup.dirs',
        'Заведи 2–3 направления',
        'Курс → «Добавить направление»',
        'сам: активных направлений ≥ 2',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.cats',
        'Привяжи категории',
        'Курс → ⋮ → Категории',
        'сам: у каждого активного направления ≥ 1 категория',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.ladder',
        'Напиши лестницу вех',
        'Курс → карточка → «Добавить веху»',
        'сам: у каждого активного ≥ 3 вехи',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.windows',
        'Задай окна сессий',
        'Настройки → Таймер → Расписание сессий',
        'сам: расписание не пусто',
        HelpTarget.settingsTimer,
        optional: true,
      ),
      HelpStep(
        'setup.distract',
        'Отметь отвлекающие окна',
        'Разбор → Окна → флажок',
        'сам: есть хотя бы одна отметка',
        HelpTarget.reviewWindows,
        windowsOnly: true,
      ),
      HelpStep(
        'setup.ai',
        'Подключи ИИ',
        'Настройки → ИИ',
        'сам: ключ задан',
        HelpTarget.settingsAi,
        optional: true,
      ),
    ],
  ),
  HelpStage(
    'Неделя наблюдения',
    'Ничего не исправляем — отмечаем. Через неделю будет с чем сравнить.',
    [
      HelpStep(
        'observe.checkin',
        'Отмечай сон утром',
        'Таймер → Карточка дня',
        'сам: ≥ 3 утра из последних 7',
        HelpTarget.timer,
      ),
      HelpStep(
        'observe.causes',
        'Отвечай на сигналы причиной',
        'Лист эпизода',
        'сам: ≥ 5 эпизодов с причиной за 7 дней',
        null,
      ),
      HelpStep(
        'observe.frog',
        'Держи день «🐸 + 2»',
        'Задачи',
        'сам: ≥ 3 дня с помидором по 🐸 за 7 дней',
        HelpTarget.tasks,
      ),
      HelpStep(
        'observe.nofix',
        'Ничего не исправляй — только отмечай',
        '—',
        'вручную',
        null,
      ),
    ],
  ),
  HelpStage(
    'Первый эксперимент',
    'Одна гипотеза на неделю. Способы из листа эпизода теперь предлагаются.',
    [
      HelpStep(
        'exp.read',
        'В понедельник прочитай разбор недели',
        'Разбор → Неделя',
        'вручную',
        HelpTarget.review,
      ),
      HelpStep(
        'exp.take',
        'Возьми эксперимент',
        'Разбор → Эксперимент',
        'сам: у текущей недели есть эксперимент',
        HelpTarget.review,
      ),
      HelpStep(
        'exp.strategies',
        'Пробуй способы из листа',
        'Лист эпизода → шаг 2',
        'сам: ≥ 3 эпизода со способом за 7 дней',
        null,
      ),
      HelpStep(
        'exp.firststep',
        'Дай 🐸 первый шаг',
        'Задачи → задача → План старта',
        'сам: у задачи в «Сегодня» есть первый шаг',
        HelpTarget.tasks,
      ),
    ],
  ),
  HelpStage(
    '«Если — то» и разгон',
    'Привязываем старт к ситуации и учимся начинать с малого.',
    [
      HelpStep(
        'plan.ifthen',
        'Поставь «если — то» для 🐸',
        'Задачи → задача → План старта → «Когда…»',
        'сам: у задачи в «Сегодня» есть «Когда»',
        HelpTarget.tasks,
      ),
      HelpStep(
        'plan.verdict',
        'Вынеси вердикт прошлому эксперименту',
        'Разбор → Эксперимент',
        'сам: у прошлой недели есть вердикт',
        HelpTarget.review,
      ),
      HelpStep(
        'plan.warmup',
        'Начни хоть раз с разгона',
        'Лист эпизода → «Только 10 минут»',
        'сам: есть эпизод со способом «Только 10 минут»',
        null,
      ),
    ],
  ),
  HelpStage(
    'Свой ритм',
    'Оставляем то, что сработало именно у тебя, и смотрим раз в месяц.',
    [
      HelpStep(
        'own.scale',
        'Пройди шкалу откладывания',
        'Разбор → Шкала',
        'сам: шкала пройдена в этом месяце',
        HelpTarget.review,
      ),
      HelpStep(
        'own.compare',
        'Сравни с неделей наблюдения',
        'Разбор → плитки, строка «база»',
        'вручную',
        HelpTarget.review,
      ),
      HelpStep(
        'own.keep',
        'Оставь работающее, брось остальное',
        'Разбор → Эксперимент',
        'вручную',
        HelpTarget.review,
      ),
      HelpStep(
        'own.month',
        'Раз в месяц — разбор на Курсе',
        'Курс → баннер',
        'вручную',
        HelpTarget.course,
      ),
    ],
  ),
];

const _sourcesRu = <({String title, String url})>[
  (
    title:
        'van Eerde & Klingsieck, 2018 — метаанализ вмешательств против '
        'откладывания',
    url: 'https://ris.uni-paderborn.de/record/29118',
  ),
  (
    title: 'Rozental и др., 2015 — интернет-КПТ, РКИ',
    url: 'https://pubmed.ncbi.nlm.nih.gov/25939016/',
  ),
  (
    title: 'Sheeran, Listrom, Gollwitzer, 2024 — планы «если — то», 642 теста',
    url: 'https://kops.uni-konstanz.de/handle/123456789/69905',
  ),
  (
    title: 'Klimczak и др., 2023 — онлайн-ACT, 53 РКИ',
    url: 'https://informahealthcare.com/doi/full/10.1080/16506073.2023.2178498',
  ),
  (
    title: 'Furukawa и др., 2025 — RESiLIENT, навыки КПТ в приложении',
    url: 'https://www.kyoto-u.ac.jp/en/research-news/2025-04-25',
  ),
  (
    title: 'Wohl, Pychyl, Bennett, 2010 — самопрощение и откладывание',
    url: 'https://doi.org/10.1016/j.paid.2010.01.029',
  ),
  (
    title: 'Lee и др., 2025 — Moa, чат-бот в планировщике',
    url: 'https://mhealth.jmir.org/2025/1/e53133',
  ),
];

// ---------------------------------------------------------------------------
// English (перевод, тот же порядок и те же блоки)
// ---------------------------------------------------------------------------

const _en = <HelpSection>[
  HelpSection('start', '🚀', 'Where to start', [
    Lead(
      'This is more than a timer. There are three layers: planning (what '
      'matters), doing (pomodoros) and self-observation (what gets in the '
      'way and what helps). Adopt it in stages: a stage is about a week.',
    ),
    PathBlock(),
    Tip(
      'Checks appear on their own when the data shows the step is done. You '
      'only check by hand what the app cannot see.',
    ),
  ]),
  HelpSection('levels', '🧭', 'How it fits together', [
    Lead(
      'Four levels, each 5–10 times bigger than the one below. That is why a '
      'direction ends up with 6–12 milestones — a list that fits on screen.',
    ),
    Steps([
      (
        where: 'Direction',
        what: '3–12 months. 2–4 active, the rest on pause.',
      ),
      (
        where: 'Milestone',
        what: '1–3 weeks. An outcome you can check with a yes or a no.',
      ),
      (
        where: '⭐ Sprint task',
        what: 'days. The commitment of the week, moves the milestone.',
      ),
      (where: '🍅 Pomodoro', what: '25 minutes. The unit of work.'),
    ]),
    Heading('A category is a project'),
    Para(
      'A direction holds a list of categories. Everything done in those '
      'categories counts toward it automatically — including past history. '
      'You never link tasks to a direction by hand.',
    ),
    Heading('A direction\'s "Why"'),
    Para(
      'The direction\'s ⋮ menu has a "Why" item: one line about what will '
      'change in your life once the direction is done. It shows on the card '
      'and in `Курс.md`, and the "Why this matters to me" approach shows it '
      'when a task feels pointless.',
    ),
    Heading('Buckets are deadlines, the sprint is ⭐'),
    Para(
      'Inbox, Tomorrow, This week, Later — when to do it. The sprint is only '
      'tasks with ⭐. A task can sit in the Inbox and still be in the sprint.',
    ),
    Heading('"Today"'),
    Bullets([
      (
        term: 'NOW',
        text: '— the top task of the list. Only one is in progress.',
      ),
      (
        term: '🐸 Frog',
        text:
            '— the most unpleasant task of the day, goes first. Cleared at '
            '05:00.',
      ),
      (
        term: 'Days',
        text: 'run from 05:00 to 05:00: a pomodoro at 00:30 is still yesterday.',
      ),
    ]),
    Go('Open Course', HelpTarget.course),
  ]),
  HelpSection('day', '☀️', 'One day', [
    Heading('Morning — 2 minutes'),
    Steps([
      (
        where: 'Timer → Day card',
        what: 'rate your sleep and energy. Two taps.',
      ),
      (
        where: 'Tasks',
        what: 'build "Today": the 🐸 and two more tasks. No more.',
      ),
      (
        where: 'Tasks',
        what:
            'put the 🐸 on the most unpleasant one. Open it and fill in '
            '"First step" in "Start plan".',
      ),
      (where: 'Timer', what: 'check the NOW card and press Space.'),
    ]),
    Heading('Work'),
    Bullets([
      (
        term: 'One task.',
        text: 'The top one is in progress. The others wait.',
      ),
      (
        term: 'A thought or a new chore',
        text:
            '— `Ctrl+N`, `Enter`: it flies into the Inbox and the day stays '
            'intact.',
      ),
      (
        term: 'Not going',
        text:
            '— the "Not going" button next to Start, or the "Stuck?" chip. '
            'One cause, one method.',
      ),
      (
        term: 'Do not feel like starting',
        text: '— a 10-minute warm-up. After it you may honestly stop.',
      ),
      (
        term: 'Stopped a pomodoro',
        text:
            '— "Where did you stop?" in one line. If you stopped because you '
            'did not finish, mark the cause.',
      ),
    ]),
    Heading('Evening — 5 seconds'),
    Para('Day card: "How was your day?". That is all.'),
    Tip(
      'Manual input is under a minute a day. The app counts delays, '
      'postponements and distractions itself.',
    ),
    Go('Open Timer', HelpTarget.timer),
  ]),
  HelpSection('week', '📅', 'Week and month', [
    Heading('Monday — 10 minutes'),
    Steps([
      (
        where: 'Review → Week',
        what: 'look at the tiles and the frequent causes.',
      ),
      (
        where: 'Review → Experiment',
        what:
            'give last week a verdict. The automatic verdict can be '
            'corrected.',
      ),
      (
        where: 'Review → Experiment',
        what: 'take a new one: the suggested one or your own.',
      ),
      (
        where: 'Sprint',
        what:
            '"Take the next step": the milestone of the week is filled in '
            'from the ladder.',
      ),
      (
        where: 'Tasks',
        what: 'put ⭐ on 2–3 tasks that move this step.',
      ),
    ]),
    Heading('When a step is done'),
    Para(
      'Sprint → "Close milestone". The next one fills in by itself, and the '
      'closing stays in the Course feed for good. An unfinished step does not '
      'burn — on Monday you take it again.',
    ),
    Heading('Once a month — 10 minutes'),
    Steps([
      (
        where: 'Course',
        what:
            'the monthly review banner. For every stuck direction: "Pause" or '
            '"Make it No. 1".',
      ),
      (
        where: 'Review',
        what:
            'the procrastination scale, 9 questions. The card appears in the '
            'first week of the month.',
      ),
    ]),
    Go('Open Review', HelpTarget.review),
  ]),
  HelpSection('stuck', '🧱', 'When it is not going', [
    Lead(
      'Procrastination is not laziness or a character flaw. It is a way to '
      'step away for a moment from the unpleasant feeling a task causes. What '
      'helps is not "pull yourself together" but understanding the feeling '
      'and making the way into the task smaller.',
    ),
    Heading('Signals — the app catches them itself'),
    Bullets([
      (
        term: 'Idle',
        text:
            '— the timer has stood for 10 minutes while there are tasks: a '
            '"Stuck?" chip appears. On Windows, after 15 minutes, a single '
            'notification if you are at the computer.',
      ),
      (
        term: 'Distraction',
        text:
            '— a flagged window stays open for a minute during a pomodoro: '
            'a notification and a chip.',
      ),
      (
        term: 'Postponed',
        text:
            '— you put off a task that is already due. From the third time — '
            'a ↻3 badge.',
      ),
      (
        term: '🐸 untouched',
        text:
            '— no pomodoro on the frog all day: the Day card tells you about '
            'it in the morning.',
      ),
      (
        term: 'Early stop',
        text: '— the cause in the "Where did you stop?" window.',
      ),
      (term: 'You noticed', text: '— the "Not going" button.'),
    ]),
    Para(
      'Answering is optional. A signal without an answer still goes into the '
      'review.',
    ),
    Heading('Episode sheet — three steps'),
    Steps([
      (
        where: 'Cause',
        what: 'one tap. A thought is optional, in one line.',
      ),
      (
        where: 'Method',
        what:
            'the one that helped you most is first. Does not fit — "Another '
            'method".',
      ),
      (
        where: 'Action',
        what: 'the button saves and starts the timer. The sheet closes.',
      ),
    ]),
    Heading('Seven causes'),
    Bullets([
      (
        term: 'Not sure where to start',
        text: '— the task is vague, it has no first action.',
      ),
      (term: 'Too big', text: '— no end in sight, scary to begin.'),
      (term: 'Boring', text: '— no interest and no quick reward.'),
      (
        term: "Afraid it won't be good",
        text: '— perfectionism, fear of judgment.',
      ),
      (term: 'No energy', text: '— it is about your state, not the task.'),
      (
        term: "Don't see the point",
        text: '— the task is not tied to what matters to you.',
      ),
      (
        term: 'Interrupted',
        text:
            '— an outside disturbance. It is not procrastination, but it '
            'counts too.',
      ),
    ]),
    Heading('Nine methods'),
    Bullets([
      (
        term: 'First step in 5 minutes',
        text:
            '— when it is unclear or too big. Write down the very first '
            'physical action. Not a decision — just the way in.',
      ),
      (
        term: 'Just 10 minutes',
        text:
            '— when it is boring or you have no energy. A 10-minute warm-up, '
            'then you may stop. Usually you will not want to.',
      ),
      (
        term: 'An "if — then" plan',
        text:
            '— "When ___, I ___". It works through repetition, which is why '
            'the plan is shown in the morning and in NOW.',
      ),
      (
        term: 'Shrink the task',
        text:
            '— the smallest version that still counts as a step forward. Do '
            'it first.',
      ),
      (
        term: 'Check the thought',
        text:
            '— a thought is a hypothesis, not a fact. What do you know for '
            'sure? How could you put it more accurately?',
      ),
      (
        term: 'Take the feeling along',
        text:
            '— "I notice the thought that…". Do not wait until it stops '
            'being scary.',
      ),
      (
        term: 'Why does this matter to me',
        text:
            '— recall the "why" of the direction. If the task is not about '
            'your goals, it belongs in the Inbox.',
      ),
      (
        term: 'An honest rest',
        text:
            '— 10 minutes without a screen: water, a window, a walk. Then a '
            'warm-up.',
      ),
      (
        term: 'Remove the distraction',
        text:
            '— close the tab, put the phone away; the thought that '
            'distracted you goes to the Inbox.',
      ),
    ]),
    Warn(
      'The first week is the observation week. Methods are not offered '
      '(except "Help anyway"): without it there is nothing to compare with '
      'later.',
    ),
  ]),
  HelpSection('review', '🔍', 'Review and experiments', [
    Heading('Week tiles'),
    Bullets([
      (
        term: 'First pomodoro',
        text:
            '— how late you are to the first session window; without a '
            'schedule, the time of the first pomodoro. Less is better.',
      ),
      (
        term: 'Idle',
        text: '— the average time between pomodoros. Less is better.',
      ),
      (
        term: '🐸 first',
        text: '— on how many days the frog was the first pomodoro.',
      ),
      (
        term: 'Postponed',
        text: '— how many times you put off tasks that were already due.',
      ),
      (
        term: 'Distractions',
        text:
            '— the share of pomodoro time in flagged windows. Windows only.',
      ),
    ]),
    Para(
      'The arrow compares with last week, "base" with the observation week. '
      '"—" means "not enough data", not zero.',
    ),
    Heading('Experiment of the week'),
    Para(
      'One hypothesis a week, for example "If the 🐸 has a first step, I '
      'start earlier". The metric is counted for you. At the end of the week '
      'comes a verdict: 15% better — "works", 15% worse — "worse", otherwise '
      '"no difference". Fewer than three days of data — "not enough data".',
    ),
    Para('A method that works moves to the top of the episode sheet by itself.'),
    Tip(
      'A week is short. "No difference" is a reason to repeat the experiment '
      'for another week, not to drop it.',
    ),
    Heading('Well-being and work'),
    Para(
      'The link of sleep and energy to idle time and the 🐸 appears once both '
      'the good and the bad days have at least three days. It is an '
      'observation, not proof.',
    ),
    Heading('Procrastination scale'),
    Para(
      '9 questions once a month. The metrics show behavior, the scale shows '
      'how you feel about it yourself. A lower score means less '
      'procrastination.',
    ),
    Go('Open Review', HelpTarget.review),
  ]),
  HelpSection('windows', '🪟', 'Windows and distractions', [
    Lead(
      'Windows only. The tracker records the active window every 5 seconds. '
      'The data stays on this computer only: it goes neither to sync nor to '
      'the AI; windows during pomodoros are kept for 60 days, those outside '
      'pomodoros for 14.',
    ),
    Heading('Where to look'),
    Bullets([
      (
        term: 'Review → Windows',
        text: '— the whole day: apps, tabs, share of distractions.',
      ),
      (
        term: 'Task → ⋮ → "Task windows"',
        text: '— what was open during all pomodoros of this task.',
      ),
      (term: 'Done → ⋮ → "What was open"', text: '— one pomodoro.'),
      (
        term: 'Review → Episodes → "What was instead"',
        text: '— what you were busy with during the idle time before the start.',
      ),
    ]),
    Heading('Flag distractions'),
    Para(
      'A flag next to YouTube, social networks, messengers — right in the '
      'window list. The distraction signal, the "Distractions" tile and the '
      'red rows depend on the flags.',
    ),
    Tip(
      'Do not flag your work browser as a whole: flag individual tabs by '
      'title.',
    ),
    Go('Open windows', HelpTarget.reviewWindows),
  ]),
  HelpSection('ai', '✨', 'AI hints', [
    Lead(
      'The AI (DeepSeek V4.1 Flash) does not chat with you. It fills in three '
      'places: first steps for a task, a hint for a thought and the weekly '
      'review. Without a key everything runs on rules.',
    ),
    Heading('Connect'),
    Steps([
      (
        where: 'platform.deepseek.com',
        what:
            'create an API key and top up the balance. A weekly review costs '
            'about a tenth of a cent.',
      ),
      (
        where: 'Settings → AI',
        what: 'turn it on, paste the key, press "Check".',
      ),
    ]),
    Heading('What is sent to DeepSeek'),
    Bullets([
      (
        term: 'Sent:',
        text:
            'the task text, its category and direction, the thought from the '
            'episode sheet, weekly numbers.',
      ),
      (
        term: 'Not sent:',
        text: 'windows, "where did you stop" notes, keys and tokens.',
      ),
    ]),
    Para(
      'The DeepSeek server is in China. The key is stored on this device '
      'only; on the phone it is entered separately.',
    ),
    Warn(
      'The AI is not a psychologist and does not diagnose. If the text shows '
      'that the trouble is not about the task, the app offers to talk to '
      'someone close or a professional instead of giving a hint.',
    ),
    Go('AI settings', HelpTarget.settingsAi),
  ]),
  HelpSection('words', '✍️', 'How to word things', [
    Heading('A milestone — checked with yes / no'),
    Compare([
      (bad: 'Work on the bot', good: 'The bot answers 3 commands in prod'),
      (
        bad: 'Sort out payments',
        good: 'The first payment from a real user went through',
      ),
      (bad: 'Improve my English', good: 'Passed an interview in English'),
    ]),
    Heading('A task — can be started in 5 minutes'),
    Compare([
      (bad: 'Build payments', good: 'Connect the Stripe webhook'),
      (bad: 'Write an article', good: 'Sketch a 5-point outline of the article'),
    ]),
    Heading('A first step — a physical action'),
    Compare([
      (bad: 'Figure out the API', good: 'Open the API docs → Auth section'),
      (bad: 'Start the report', good: 'Create the file and write the title'),
    ]),
    Heading('"If — then" — a concrete situation'),
    Compare([
      (
        bad: "I'll do it in the morning",
        good: "When I sit down after breakfast, I'll open api.dart",
      ),
      (
        bad: 'When I have time',
        good: 'At 14:00 after lunch — the first step of the 🐸',
      ),
    ]),
    Para(
      'On the left are pastimes, they never end. On the right are actions and '
      'results, they get closed.',
    ),
  ]),
  HelpSection('mistakes', '⚠️', 'Common mistakes', [
    Bullets([
      (
        term: 'Five active directions.',
        text: 'It does not work. Two or three, the rest on pause.',
      ),
      (
        term: 'A milestone for a quarter.',
        text: 'Too big — you cannot see movement. A step is 1–3 weeks.',
      ),
      (
        term: 'The ladder as a to-do list.',
        text: 'A step is an outcome. Chores live in tasks with ⭐.',
      ),
      (
        term: 'Eight tasks a day.',
        text: 'That is a wish list, not a plan. The 🐸 and two more.',
      ),
      (
        term: 'A direction without categories.',
        text: 'Attention to it is not counted.',
      ),
      (
        term: 'Skipping the observation week.',
        text: 'Then there is nothing to compare with.',
      ),
      (
        term: 'Three experiments at once.',
        text: 'It is unclear what worked. One a week.',
      ),
      (
        term: 'Scolding yourself for an empty day.',
        text:
            'There are no streaks here on purpose: yesterday is data, not a '
            'verdict.',
      ),
    ]),
  ]),
  HelpSection('keys', '⌨️', 'Keys and input', [
    Steps([
      (where: 'Space', what: 'start / pause.'),
      (where: 'Esc Esc', what: 'stop (second press within 1.5 s).'),
      (where: 'Ctrl+N', what: 'add a task from anywhere.'),
      (
        where: '+ / −',
        what: 'pomodoros of the first task, with Shift — by 4.',
      ),
      (where: 'F1', what: 'this help.'),
    ]),
    Heading('Smart input'),
    Para(
      '`#category Description ~3` — category, description and 3 pomodoros. '
      '`Enter` — to the Inbox, `Ctrl+Enter` — to "Today". Click the pomodoro '
      'count: +1, with Alt — −1, with Shift — ×4.',
    ),
  ]),
  HelpSection('science', '📚', 'Why it works', [
    Lead(
      'The methods come from approaches that were tested in studies. They are '
      'self-observation tools, not treatment.',
    ),
    Bullets([
      (
        term: 'CBT',
        text:
            'reduces procrastination more than other approaches (a '
            'meta-analysis of 24 studies). In an internet program the effect '
            'was there even without a specialist.',
      ),
      (
        term: '"If — then" plans',
        text:
            'help more the more concrete the situation is and the more often '
            'you repeat the plan (642 tests).',
      ),
      (
        term: 'ACT',
        text:
            '— do not wait for the unpleasant feeling to go away, act for '
            'what matters (53 studies of online programs).',
      ),
      (
        term: 'Behavioral activation',
        text: '— action before motivation.',
      ),
      (
        term: 'Self-forgiveness',
        text: 'after procrastinating reduces procrastination the next time.',
      ),
      (
        term: 'The "observation → cause → method → reflection" loop',
        text: 'inside a planner was tested with the chatbot Moa.',
      ),
    ]),
    Sources(),
    Warn(
      'If low mood, anxiety or insomnia last for weeks, that is a reason to '
      'talk to a specialist, not to reconfigure the app.',
    ),
  ]),
];

const _stagesEn = <HelpStage>[
  HelpStage(
    'Setup',
    'Once, 15 minutes. Without directions and categories the review does not '
    'know where your attention goes.',
    [
      HelpStep(
        'setup.dirs',
        'Create 2–3 directions',
        'Course → "Add direction"',
        'auto: active directions ≥ 2',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.cats',
        'Link categories',
        'Course → ⋮ → Categories',
        'auto: every active direction has ≥ 1 category',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.ladder',
        'Write the milestone ladder',
        'Course → card → "Add milestone"',
        'auto: every active direction has ≥ 3 milestones',
        HelpTarget.course,
      ),
      HelpStep(
        'setup.windows',
        'Set session windows',
        'Settings → Timer → Session schedule',
        'auto: the schedule is not empty',
        HelpTarget.settingsTimer,
        optional: true,
      ),
      HelpStep(
        'setup.distract',
        'Flag distracting windows',
        'Review → Windows → flag',
        'auto: at least one flag exists',
        HelpTarget.reviewWindows,
        windowsOnly: true,
      ),
      HelpStep(
        'setup.ai',
        'Connect the AI',
        'Settings → AI',
        'auto: the key is set',
        HelpTarget.settingsAi,
        optional: true,
      ),
    ],
  ),
  HelpStage(
    'Observation week',
    'We fix nothing — we only mark. In a week there will be something to '
    'compare with.',
    [
      HelpStep(
        'observe.checkin',
        'Rate your sleep in the morning',
        'Timer → Day card',
        'auto: ≥ 3 mornings of the last 7',
        HelpTarget.timer,
      ),
      HelpStep(
        'observe.causes',
        'Answer signals with a cause',
        'Episode sheet',
        'auto: ≥ 5 episodes with a cause in 7 days',
        null,
      ),
      HelpStep(
        'observe.frog',
        'Keep the "🐸 + 2" day',
        'Tasks',
        'auto: ≥ 3 days with a pomodoro on the 🐸 in 7 days',
        HelpTarget.tasks,
      ),
      HelpStep(
        'observe.nofix',
        'Fix nothing — only mark',
        '—',
        'manual',
        null,
      ),
    ],
  ),
  HelpStage(
    'First experiment',
    'One hypothesis a week. Methods from the episode sheet are offered now.',
    [
      HelpStep(
        'exp.read',
        'On Monday, read the weekly review',
        'Review → Week',
        'manual',
        HelpTarget.review,
      ),
      HelpStep(
        'exp.take',
        'Take an experiment',
        'Review → Experiment',
        'auto: the current week has an experiment',
        HelpTarget.review,
      ),
      HelpStep(
        'exp.strategies',
        'Try methods from the sheet',
        'Episode sheet → step 2',
        'auto: ≥ 3 episodes with a method in 7 days',
        null,
      ),
      HelpStep(
        'exp.firststep',
        'Give the 🐸 a first step',
        'Tasks → task → Start plan',
        'auto: a task in "Today" has a first step',
        HelpTarget.tasks,
      ),
    ],
  ),
  HelpStage(
    '"If — then" and warm-up',
    'We tie the start to a situation and learn to begin small.',
    [
      HelpStep(
        'plan.ifthen',
        'Set an "if — then" for the 🐸',
        'Tasks → task → Start plan → "When…"',
        'auto: a task in "Today" has a "When"',
        HelpTarget.tasks,
      ),
      HelpStep(
        'plan.verdict',
        'Give last experiment a verdict',
        'Review → Experiment',
        'auto: last week has a verdict',
        HelpTarget.review,
      ),
      HelpStep(
        'plan.warmup',
        'Start with a warm-up at least once',
        'Episode sheet → "Just 10 minutes"',
        'auto: an episode with the "Just 10 minutes" method exists',
        null,
      ),
    ],
  ),
  HelpStage(
    'Your own rhythm',
    'We keep what worked for you and look once a month.',
    [
      HelpStep(
        'own.scale',
        'Take the procrastination scale',
        'Review → Scale',
        'auto: the scale was taken this month',
        HelpTarget.review,
      ),
      HelpStep(
        'own.compare',
        'Compare with the observation week',
        'Review → tiles, the "base" line',
        'manual',
        HelpTarget.review,
      ),
      HelpStep(
        'own.keep',
        'Keep what works, drop the rest',
        'Review → Experiment',
        'manual',
        HelpTarget.review,
      ),
      HelpStep(
        'own.month',
        'Once a month — review on the Course',
        'Course → banner',
        'manual',
        HelpTarget.course,
      ),
    ],
  ),
];

const _sourcesEn = <({String title, String url})>[
  (
    title:
        'van Eerde & Klingsieck, 2018 — meta-analysis of procrastination '
        'interventions',
    url: 'https://ris.uni-paderborn.de/record/29118',
  ),
  (
    title: 'Rozental et al., 2015 — internet-based CBT, RCT',
    url: 'https://pubmed.ncbi.nlm.nih.gov/25939016/',
  ),
  (
    title: 'Sheeran, Listrom, Gollwitzer, 2024 — "if — then" plans, 642 tests',
    url: 'https://kops.uni-konstanz.de/handle/123456789/69905',
  ),
  (
    title: 'Klimczak et al., 2023 — online ACT, 53 RCTs',
    url: 'https://informahealthcare.com/doi/full/10.1080/16506073.2023.2178498',
  ),
  (
    title: 'Furukawa et al., 2025 — RESiLIENT, CBT skills in an app',
    url: 'https://www.kyoto-u.ac.jp/en/research-news/2025-04-25',
  ),
  (
    title: 'Wohl, Pychyl, Bennett, 2010 — self-forgiveness and procrastination',
    url: 'https://doi.org/10.1016/j.paid.2010.01.029',
  ),
  (
    title: 'Lee et al., 2025 — Moa, a chatbot inside a planner',
    url: 'https://mhealth.jmir.org/2025/1/e53133',
  ),
];
