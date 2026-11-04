import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/help_content.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';

T _in<T>(AppLanguage lang, T Function() read) {
  S.lang = lang;
  return read();
}

/// Форма раздела: тип каждого блока и число элементов в нём.
List<String> _shape(HelpSection s) => [
  for (final b in s.blocks)
    switch (b) {
      Lead() => 'Lead',
      Para() => 'Para',
      Heading() => 'Heading',
      Steps(:final items) => 'Steps${items.length}',
      Bullets(:final items) => 'Bullets${items.length}',
      Compare(:final items) => 'Compare${items.length}',
      Tip() => 'Tip',
      Warn() => 'Warn',
      Go(:final target) => 'Go:${target.name}',
      PathBlock() => 'Path',
      Sources() => 'Sources',
    },
];

void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  final ru = _in(AppLanguage.ru, helpSections);
  final en = _in(AppLanguage.en, helpSections);

  test('одинаковые id разделов в том же порядке', () {
    expect(en.map((s) => s.id), ru.map((s) => s.id));
    expect(ru.map((s) => s.id), [
      'start',
      'levels',
      'day',
      'week',
      'stuck',
      'review',
      'windows',
      'ai',
      'words',
      'mistakes',
      'keys',
      'science',
    ]);
  });

  test('одинаковое число блоков каждого типа в каждом разделе', () {
    for (var i = 0; i < ru.length; i++) {
      expect(_shape(en[i]), _shape(ru[i]), reason: ru[i].id);
      expect(en[i].emoji, ru[i].emoji, reason: ru[i].id);
    }
  });

  test('ни одна строка разделов не пуста; перевод не копия русского', () {
    void check(String id, String s) {
      expect(s.trim(), isNotEmpty, reason: id);
    }

    for (final lang in AppLanguage.values) {
      for (final s in _in(lang, helpSections)) {
        check(s.id, s.emoji);
        check(s.id, s.title);
        for (final text in sectionTexts(s)) {
          check(s.id, text);
        }
        for (final b in s.blocks) {
          switch (b) {
            case Bullets(:final items):
              for (final i in items) {
                check(s.id, i.term);
                check(s.id, i.text);
              }
            case Steps(:final items):
              for (final i in items) {
                check(s.id, i.where);
                check(s.id, i.what);
              }
            default:
          }
        }
      }
    }
    // Заголовки всех разделов отличаются: английский действительно написан.
    for (var i = 0; i < ru.length; i++) {
      expect(en[i].title, isNot(ru[i].title), reason: ru[i].id);
    }
  });

  test('одинаковые id, цели и флаги шагов пути; строки не пусты', () {
    final ruStages = _in(AppLanguage.ru, adoptionStages);
    final enStages = _in(AppLanguage.en, adoptionStages);
    expect(enStages.length, 5);
    expect(enStages.length, ruStages.length);
    for (var i = 0; i < ruStages.length; i++) {
      expect(enStages[i].steps.map((s) => s.id), ruStages[i].steps.map((s) => s.id));
      expect(
        enStages[i].steps.map((s) => (s.target, s.optional, s.windowsOnly)),
        ruStages[i].steps.map((s) => (s.target, s.optional, s.windowsOnly)),
      );
    }
    for (final stage in [...ruStages, ...enStages]) {
      expect(stage.title.trim(), isNotEmpty);
      expect(stage.hint.trim(), isNotEmpty);
      for (final step in stage.steps) {
        expect(step.id.trim(), isNotEmpty);
        expect(step.title.trim(), isNotEmpty, reason: step.id);
        expect(step.where.trim(), isNotEmpty, reason: step.id);
        expect(step.rule.trim(), isNotEmpty, reason: step.id);
      }
    }
    final ids = [for (final s in ruStages) ...s.steps.map((x) => x.id)];
    expect(ids.toSet().length, ids.length, reason: 'id шагов уникальны');
    expect(ids.length, 21);
  });

  test('источники: те же ссылки, названия не пусты', () {
    final ruSources = _in(AppLanguage.ru, helpSources);
    final enSources = _in(AppLanguage.en, helpSources);
    expect(enSources.map((s) => s.url), ruSources.map((s) => s.url));
    expect(ruSources, hasLength(7));
    for (final s in [...ruSources, ...enSources]) {
      expect(s.title.trim(), isNotEmpty);
      expect(Uri.parse(s.url).scheme, 'https');
    }
  });

  test('инлайн-разметка (** и `) парная в каждой строке документа', () {
    for (final lang in AppLanguage.values) {
      S.lang = lang;
      for (final line in helpMarkdown().split('\n')) {
        expect('**'.allMatches(line).length.isEven, isTrue, reason: line);
        expect('`'.allMatches(line).length.isEven, isTrue, reason: line);
      }
    }
  });

  test('windows: в тексте оба срока хранения', () {
    String text(AppLanguage lang) => _in(
      lang,
      () => helpSections().firstWhere((s) => s.id == 'windows'),
    ).blocks.whereType<Lead>().single.text;
    final ruText = text(AppLanguage.ru);
    expect(ruText, contains('60'));
    expect(ruText, contains('14'));
    final enText = text(AppLanguage.en);
    expect(enText, contains('60'));
    expect(enText, contains('14'));
  });

  group('поиск', () {
    HelpSection section(String id) => ru.firstWhere((s) => s.id == id);

    test('«разгон» находит day, stuck и start (через путь)', () {
      S.lang = AppLanguage.ru;
      final found = [
        for (final s in helpSections())
          if (sectionMatches(s, 'разгон')) s.id,
      ];
      expect(found, ['start', 'day', 'stuck']);
    });

    test('регистр и пробелы вокруг не важны; пустой запрос — все', () {
      S.lang = AppLanguage.ru;
      expect(sectionMatches(section('day'), '  РАЗГОН '), isTrue);
      expect(sectionMatches(section('keys'), ''), isTrue);
      expect(sectionMatches(section('keys'), 'ничегонетакого'), isFalse);
    });

    test('ищет по заголовку, разметка не мешает', () {
      S.lang = AppLanguage.ru;
      expect(sectionMatches(section('keys'), 'клавиши'), isTrue);
      // В тексте `Ctrl+N` стоит в кавычках кода.
      expect(sectionMatches(section('day'), 'ctrl+n'), isTrue);
      expect(sectionMatches(section('day'), '`'), isFalse);
    });

    test('в разделе с путём ищет по заголовкам и «где» шагов', () {
      S.lang = AppLanguage.ru;
      final start = section('start');
      expect(sectionMatches(start, 'расписание сессий'), isTrue);
      expect(sectionMatches(start, 'Карточка дня'), isTrue);
    });
  });

  test('plainText снимает ** и `', () {
    expect(plainText('**жирный** и `код`'), 'жирный и код');
  });
}
