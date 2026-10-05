import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

void main() {
  group('addTick', () {
    test('суммирует секунды одного ключа', () {
      final day = <String, ActivityEntry>{};
      addTick(day, app: 'code.exe', seconds: 5, inFocus: false);
      addTick(day, app: 'code.exe', seconds: 5, inFocus: false);
      addTick(day, app: 'chrome.exe', title: 'YouTube', seconds: 5, inFocus: false);
      expect(day, hasLength(2));
      expect(day['code.exe|']!.seconds, 10);
      expect(day['chrome.exe|YouTube']!.seconds, 5);
    });

    test('focusSeconds копится только в помидоре', () {
      final day = <String, ActivityEntry>{};
      addTick(day, app: 'code.exe', seconds: 5, inFocus: true);
      addTick(day, app: 'code.exe', seconds: 5, inFocus: false);
      addTick(day, app: 'code.exe', seconds: 5, inFocus: true);
      final entry = day['code.exe|']!;
      expect(entry.seconds, 15);
      expect(entry.focusSeconds, 10);
    });

    test('вкладки одного браузера — разные записи, ключ — название вкладки', () {
      final day = <String, ActivityEntry>{};
      addTick(day, app: 'chrome.exe', title: 'A', seconds: 5, inFocus: false);
      addTick(day, app: 'chrome.exe', title: 'B', seconds: 5, inFocus: false);
      expect(day.values.map((e) => e.key), unorderedEquals(['A', 'B']));
      expect(ActivityEntry(app: 'code.exe').key, 'code.exe');
    });
  });

  group('browserTabTitle', () {
    test('срезает « - Google Chrome»', () {
      expect(
        browserTabTitle('chrome.exe', 'YouTube - Google Chrome'),
        'YouTube',
      );
    });

    test('срезает « — Mozilla Firefox» и дефис в самом названии остаётся', () {
      expect(
        browserTabTitle('firefox.exe', 'Dart - язык — Mozilla Firefox'),
        'Dart - язык',
      );
    });

    test('Edge с невидимым пробелом и профилем', () {
      expect(
        browserTabTitle('msedge.exe', 'Почта - Microsoft\u200B Edge'),
        'Почта',
      );
      expect(
        browserTabTitle('chrome.exe', 'Docs - Google Chrome - Работа'),
        'Docs',
      );
    });

    test('регистр exe не важен, голое имя браузера — пустое название', () {
      expect(browserTabTitle('Brave.exe', 'Пример - Brave'), 'Пример');
      expect(browserTabTitle('chrome.exe', 'Google Chrome'), '');
    });

    test('для не-браузеров заголовок игнорируется', () {
      expect(browserTabTitle('code.exe', 'main.dart - Visual Studio Code'), '');
      expect(browserTabTitle('notepad.exe', 'secret.txt - Notepad'), '');
    });
  });

  group('pruneDays', () {
    test('удаляет дни старше 60, свежие оставляет', () {
      final today = DateTime(2026, 10, 5);
      final days = <String, int>{
        '2026-10-05': 1,
        '2026-08-07': 2, // 60-й день включая сегодня — остаётся
        '2026-08-06': 3, // 61-й — удаляется
        '2025-01-01': 4,
      };
      pruneDays(days, today);
      expect(days.keys, unorderedEquals(['2026-10-05', '2026-08-07']));
    });

    test('учитывает параметр keep', () {
      final days = <String, int>{'2026-10-05': 1, '2026-10-04': 2, '2026-10-03': 3};
      pruneDays(days, DateTime(2026, 10, 5), keep: 2);
      expect(days.keys, unorderedEquals(['2026-10-05', '2026-10-04']));
    });
  });

  group('ActivityData', () {
    test('JSON туда-обратно: дни и отвлекающие', () {
      final data = ActivityData();
      addTick(
        data.days.putIfAbsent('2026-10-05', () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 120,
        inFocus: true,
      );
      data.distracting.add('YouTube');
      final copy = ActivityData.fromJson(data.toJson());
      final entry = copy.days['2026-10-05']!['chrome.exe|YouTube']!;
      expect(entry.seconds, 120);
      expect(entry.focusSeconds, 120);
      expect(copy.distracting, {'YouTube'});
    });

    test('битый JSON даёт пустые данные', () {
      expect(ActivityData.fromJson('мусор').days, isEmpty);
      expect(ActivityData.fromJson({'2026-10-05': 'x'}).days, isEmpty);
    });
  });
}
