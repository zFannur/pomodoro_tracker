import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/help_content.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';

/// docs/КАК-ПОЛЬЗОВАТЬСЯ.md и docs/HOW-TO-USE.md генерируются из справки
/// приложения (ru и en). Если тест падает — документы разошлись с
/// `help_content.dart`; обновить их:
///   UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart
void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  const docs = {
    AppLanguage.ru: 'docs/КАК-ПОЛЬЗОВАТЬСЯ.md',
    AppLanguage.en: 'docs/HOW-TO-USE.md',
  };

  for (final entry in docs.entries) {
    test('${entry.value} совпадает со справкой приложения', () {
      S.lang = entry.key;
      final expected = helpMarkdown();
      final file = File(entry.value);
      if (Platform.environment['UPDATE_HELP_DOC'] == '1') {
        file.writeAsStringSync(expected);
        return;
      }
      // git на Windows может отдать файл с CRLF — на сравнение это не влияет.
      final actual = file.readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        actual,
        expected,
        reason:
            'Документ устарел: UPDATE_HELP_DOC=1 flutter test '
            'test/help_doc_test.dart',
      );
    });
  }

  for (final entry in docs.entries) {
    final lang = entry.key;
    test('${entry.value} начинается с шапки и содержит все разделы', () {
      S.lang = lang;
      final md = helpMarkdown();
      expect(
        md,
        startsWith(
          lang == AppLanguage.ru
              ? '# Как пользоваться'
              : '# How to use',
        ),
      );
      expect(
        md,
        contains('`lib/app/help_content.dart`'),
        reason: entry.value,
      );
      for (final s in helpSections()) {
        expect(md, contains('## ${s.emoji} ${s.title}'), reason: s.id);
      }
      // Путь внедрения — таблицами по этапам, источники — ссылками.
      for (final stage in adoptionStages()) {
        expect(md, contains(stage.title));
        for (final step in stage.steps) {
          expect(md, contains(step.title), reason: step.id);
        }
      }
      for (final src in helpSources()) {
        expect(md, contains('](${src.url})'));
      }
    });
  }
}
