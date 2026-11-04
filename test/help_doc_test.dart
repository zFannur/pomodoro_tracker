import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/help_content.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';

/// docs/КАК-ПОЛЬЗОВАТЬСЯ.md генерируется из справки приложения. Если тест
/// падает — документ разошёлся с `help_content.dart`; обновить его:
///   UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart
void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  test('docs/КАК-ПОЛЬЗОВАТЬСЯ.md совпадает со справкой приложения', () {
    S.lang = AppLanguage.ru;
    final expected = helpMarkdown();
    final file = File('docs/КАК-ПОЛЬЗОВАТЬСЯ.md');
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

  test('документ начинается с шапки про генерацию и содержит все разделы', () {
    S.lang = AppLanguage.ru;
    final md = helpMarkdown();
    expect(
      md,
      contains(
        'Сгенерировано из справки приложения — правь '
        '`lib/app/help_content.dart`, затем '
        '`UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart`',
      ),
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
