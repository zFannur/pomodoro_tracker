import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart' show dateKey;
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
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

  group('addSegmentTick', () {
    test('склейка тиков в один отрезок', () {
      final day = <ActivitySegment>[];
      final t0 = DateTime(2026, 10, 5, 10, 0, 0);
      addSegmentTick(day, now: t0, app: 'chrome.exe', title: 'Docs', seconds: 5);
      addSegmentTick(day, now: t0.add(const Duration(seconds: 5)), app: 'chrome.exe', title: 'Docs', seconds: 5);
      addSegmentTick(day, now: t0.add(const Duration(seconds: 10)), app: 'chrome.exe', title: 'Docs', seconds: 5);

      expect(day, hasLength(1));
      expect(day.first.from, t0.subtract(const Duration(seconds: 5)));
      expect(day.first.to, t0.add(const Duration(seconds: 10)));
      expect(day.first.app, 'chrome.exe');
      expect(day.first.title, 'Docs');
    });

    test('разрыв при смене приложения', () {
      final day = <ActivitySegment>[];
      final t0 = DateTime(2026, 10, 5, 10, 0, 0);
      addSegmentTick(day, now: t0, app: 'chrome.exe', title: 'Docs', seconds: 5);
      addSegmentTick(day, now: t0.add(const Duration(seconds: 5)), app: 'code.exe', title: '', seconds: 5);

      expect(day, hasLength(2));
      expect(day[0].app, 'chrome.exe');
      expect(day[0].title, 'Docs');
      expect(day[0].to, t0);
      expect(day[1].app, 'code.exe');
      expect(day[1].title, '');
      expect(day[1].from, t0);
      expect(day[1].to, t0.add(const Duration(seconds: 5)));
    });

    test('разрыв при паузе > 2 тиков', () {
      final day = <ActivitySegment>[];
      final t0 = DateTime(2026, 10, 5, 10, 0, 0);
      addSegmentTick(day, now: t0, app: 'chrome.exe', title: 'Docs', seconds: 5);
      // Пауза 11 сек (> 5 * 2 = 10 сек)
      final t1 = t0.add(const Duration(seconds: 11));
      addSegmentTick(day, now: t1, app: 'chrome.exe', title: 'Docs', seconds: 5);

      expect(day, hasLength(2));
      expect(day[0].from, t0.subtract(const Duration(seconds: 5)));
      expect(day[0].to, t0);
      expect(day[1].from, t1.subtract(const Duration(seconds: 5)));
      expect(day[1].to, t1);
    });
  });

  group('segmentsSummary', () {
    test('segmentsSummary с частичным пересечением окна', () {
      final base = DateTime(2026, 10, 5, 10, 0, 0);
      final segments = [
        // За пределами окна слева (09:40 - 09:50)
        ActivitySegment(
          from: base.subtract(const Duration(minutes: 20)),
          to: base.subtract(const Duration(minutes: 10)),
          app: 'notepad.exe',
        ),
        // Частично пересекает слева (09:55 - 10:10): окно с 10:00, пересечение 10 мин = 600 сек
        ActivitySegment(
          from: base.subtract(const Duration(minutes: 5)),
          to: base.add(const Duration(minutes: 10)),
          app: 'chrome.exe',
          title: 'YouTube',
        ),
        // Полностью внутри окна (10:10 - 10:20): пересечение 10 мин = 600 сек
        ActivitySegment(
          from: base.add(const Duration(minutes: 10)),
          to: base.add(const Duration(minutes: 20)),
          app: 'code.exe',
        ),
        // Ещё один отрезок того же code.exe внутри окна (10:20 - 10:25): 5 мин = 300 сек (суммарно 900 сек)
        ActivitySegment(
          from: base.add(const Duration(minutes: 20)),
          to: base.add(const Duration(minutes: 25)),
          app: 'code.exe',
        ),
        // Частично пересекает справа (10:25 - 10:35): окно до 10:30, пересечение 5 мин = 300 сек
        ActivitySegment(
          from: base.add(const Duration(minutes: 25)),
          to: base.add(const Duration(minutes: 35)),
          app: 'chrome.exe',
          title: 'GitHub',
        ),
        // За пределами окна справа (10:40 - 10:50)
        ActivitySegment(
          from: base.add(const Duration(minutes: 40)),
          to: base.add(const Duration(minutes: 50)),
          app: 'slack.exe',
        ),
      ];

      final windowFrom = base; // 10:00
      final windowTo = base.add(const Duration(minutes: 30)); // 10:30

      final summary = segmentsSummary(segments, windowFrom, windowTo);

      // Ожидаем 3 записи, отсортированные по убыванию seconds:
      // 1. code.exe: 600 + 300 = 900 сек
      // 2. chrome.exe|YouTube: 600 сек
      // 3. chrome.exe|GitHub: 300 сек
      expect(summary, hasLength(3));
      expect(summary[0].app, 'code.exe');
      expect(summary[0].seconds, 900);
      expect(summary[1].app, 'chrome.exe');
      expect(summary[1].title, 'YouTube');
      expect(summary[1].seconds, 600);
      expect(summary[2].app, 'chrome.exe');
      expect(summary[2].title, 'GitHub');
      expect(summary[2].seconds, 300);
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

    test('pruneDays чистит segments', () {
      final today = DateTime(2026, 10, 5);
      final segments = <String, List<ActivitySegment>>{
        '2026-10-05': [
          ActivitySegment(
            from: DateTime(2026, 10, 5, 10),
            to: DateTime(2026, 10, 5, 10, 25),
            app: 'code.exe',
          ),
        ],
        '2026-08-07': [
          ActivitySegment(
            from: DateTime(2026, 8, 7, 10),
            to: DateTime(2026, 8, 7, 10, 25),
            app: 'code.exe',
          ),
        ],
        '2026-08-06': [
          ActivitySegment(
            from: DateTime(2026, 8, 6, 10),
            to: DateTime(2026, 8, 6, 10, 25),
            app: 'code.exe',
          ),
        ],
        '2025-01-01': [],
      };
      pruneDays(segments, today);
      expect(segments.keys, unorderedEquals(['2026-10-05', '2026-08-07']));
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

    test('round-trip JSON с segments', () {
      final data = ActivityData();
      final seg = ActivitySegment(
        from: DateTime(2026, 10, 5, 10, 0),
        to: DateTime(2026, 10, 5, 10, 25),
        app: 'chrome.exe',
        title: 'YouTube',
      );
      data.focusSegments['2026-10-05'] = [seg];
      data.distracting.add('YouTube');
      addTick(
        data.days.putIfAbsent('2026-10-05', () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 1500,
        inFocus: true,
      );

      final copy = ActivityData.fromJson(data.toJson());
      expect(copy.focusSegments['2026-10-05'], hasLength(1));
      final copiedSeg = copy.focusSegments['2026-10-05']!.first;
      expect(copiedSeg.from, seg.from);
      expect(copiedSeg.to, seg.to);
      expect(copiedSeg.app, 'chrome.exe');
      expect(copiedSeg.title, 'YouTube');
      expect(copy.days['2026-10-05']!['chrome.exe|YouTube']!.seconds, 1500);
      expect(copy.distracting, {'YouTube'});
    });

    test('чтение старого JSON без segments', () {
      final oldJson = {
        '2026-10-05': [
          {'app': 'code.exe', 'title': '', 'seconds': 60, 'focusSeconds': 60},
        ],
        'distracting': ['code.exe'],
      };
      final data = ActivityData.fromJson(oldJson);
      expect(data.days['2026-10-05']!['code.exe|']!.seconds, 60);
      expect(data.distracting, {'code.exe'});
      expect(data.focusSegments, isEmpty);
    });

    test('битый JSON даёт пустые данные', () {
      expect(ActivityData.fromJson('мусор').days, isEmpty);
      expect(ActivityData.fromJson({'2026-10-05': 'x'}).days, isEmpty);
    });
  });

  group('ActivityCubit.segmentsFor', () {
    test('берёт отрезки в окне session.start - 1 мин .. start + minutes + 1 мин', () {
      final tracker = ActivityTracker(
        store: ActivityStore(),
        inPomodoro: () => true,
      );
      final start = DateTime(2026, 10, 5, 10, 0);
      tracker.data.focusSegments['2026-10-05'] = [
        ActivitySegment(
          from: start.subtract(const Duration(seconds: 30)),
          to: start.add(const Duration(minutes: 25, seconds: 30)),
          app: 'chrome.exe',
          title: 'YouTube',
        ),
      ];
      final cubit = ActivityCubit(tracker);
      final session = PomoSession(
        id: 's1',
        start: start,
        minutes: 25,
        category: 'work',
        task: 'test',
      );
      final rows = cubit.segmentsFor(session);
      expect(rows, hasLength(1));
      expect(rows.first.app, 'chrome.exe');
      expect(rows.first.title, 'YouTube');
      expect(rows.first.seconds, 1560);
      cubit.close();
    });
  });

  group('deleteActivity', () {
    test('за один день не трогает другие дни', () {
      final data = ActivityData();
      addTick(
        data.days.putIfAbsent('2026-10-05', () => {}),
        app: 'code.exe',
        seconds: 10,
        inFocus: false,
      );
      addTick(
        data.days.putIfAbsent('2026-10-06', () => {}),
        app: 'code.exe',
        seconds: 20,
        inFocus: false,
      );
      deleteActivity(data, {(app: 'code.exe', title: '')}, day: '2026-10-05');

      expect(data.days['2026-10-05'], isNull);
      expect(data.days['2026-10-06'], isNotNull);
      expect(data.days['2026-10-06']!['code.exe|']!.seconds, 20);
    });

    test('за все дни удаляет везде, включая отрезки', () {
      final data = ActivityData();
      final t1 = DateTime(2026, 10, 5, 10);
      final t2 = DateTime(2026, 10, 6, 10);
      addTick(
        data.days.putIfAbsent('2026-10-05', () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 10,
        inFocus: true,
      );
      addSegmentTick(
        data.focusSegments.putIfAbsent('2026-10-05', () => []),
        now: t1,
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 10,
      );
      addTick(
        data.days.putIfAbsent('2026-10-06', () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 20,
        inFocus: true,
      );
      addSegmentTick(
        data.focusSegments.putIfAbsent('2026-10-06', () => []),
        now: t2,
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 20,
      );

      deleteActivity(data, {(app: 'chrome.exe', title: 'YouTube')});

      expect(data.days['2026-10-05'], isNull);
      expect(data.days['2026-10-06'], isNull);
      expect(data.focusSegments['2026-10-05'], isNull);
      expect(data.focusSegments['2026-10-06'], isNull);
    });

    test('разные title одного браузера удаляются раздельно', () {
      final data = ActivityData();
      final day = '2026-10-05';
      addTick(
        data.days.putIfAbsent(day, () => {}),
        app: 'chrome.exe',
        title: 'Docs',
        seconds: 30,
        inFocus: true,
      );
      addTick(
        data.days.putIfAbsent(day, () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 60,
        inFocus: true,
      );
      final now = DateTime(2026, 10, 5, 10, 0);
      addSegmentTick(
        data.focusSegments.putIfAbsent(day, () => []),
        now: now,
        app: 'chrome.exe',
        title: 'Docs',
        seconds: 30,
      );
      addSegmentTick(
        data.focusSegments.putIfAbsent(day, () => []),
        now: now.add(const Duration(seconds: 30)),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 30,
      );

      deleteActivity(data, {(app: 'chrome.exe', title: 'YouTube')}, day: day);

      expect(data.days[day]!.containsKey('chrome.exe|YouTube'), isFalse);
      expect(data.days[day]!.containsKey('chrome.exe|Docs'), isTrue);
      expect(data.focusSegments[day]!.any((s) => s.title == 'YouTube'), isFalse);
      expect(data.focusSegments[day]!.any((s) => s.title == 'Docs'), isTrue);
    });

    test('опустевший день исчезает', () {
      final data = ActivityData();
      final day = '2026-10-05';
      addTick(
        data.days.putIfAbsent(day, () => {}),
        app: 'code.exe',
        seconds: 5,
        inFocus: true,
      );
      addSegmentTick(
        data.focusSegments.putIfAbsent(day, () => []),
        now: DateTime(2026, 10, 5, 10),
        app: 'code.exe',
        title: '',
        seconds: 5,
      );

      deleteActivity(data, {(app: 'code.exe', title: '')}, day: day);

      expect(data.days.containsKey(day), isFalse);
      expect(data.focusSegments.containsKey(day), isFalse);
    });

    test('distracting не меняется', () {
      final data = ActivityData();
      final day = '2026-10-05';
      addTick(
        data.days.putIfAbsent(day, () => {}),
        app: 'chrome.exe',
        title: 'YouTube',
        seconds: 10,
        inFocus: false,
      );
      data.distracting.add('YouTube');
      data.distracting.add('code.exe');

      deleteActivity(data, {(app: 'chrome.exe', title: 'YouTube')});

      expect(data.distracting, containsAll(['YouTube', 'code.exe']));
      expect(data.distracting, hasLength(2));
    });
  });

  group('ActivityCubit selection and deletion', () {
    test('выбор, сброс выбора при смене дня', () {
      final tracker = ActivityTracker(
        store: ActivityStore(),
        inPomodoro: () => true,
      );
      final today = logicalDate(clock.now());
      final todayKey = dateKey(today);
      final prevDay = DateTime(today.year, today.month, today.day - 1);
      final prevKey = dateKey(prevDay);

      addTick(
        tracker.data.days.putIfAbsent(todayKey, () => {}),
        app: 'code.exe',
        seconds: 100,
        inFocus: true,
      );
      addTick(
        tracker.data.days.putIfAbsent(todayKey, () => {}),
        app: 'chrome.exe',
        title: 'Docs',
        seconds: 200,
        inFocus: false,
      );
      addTick(
        tracker.data.days.putIfAbsent(prevKey, () => {}),
        app: 'slack.exe',
        seconds: 50,
        inFocus: false,
      );

      final cubit = ActivityCubit(tracker)..refresh();
      expect(cubit.state.rows, hasLength(2));
      expect(cubit.state.selected, isEmpty);

      final row0 = cubit.state.rows.first;
      cubit.toggleSelected(row0);
      expect(cubit.state.selected, {'${row0.app}|${row0.title}'});
      expect(cubit.state.isSelected(row0), isTrue);

      // Смена дня сбрасывает выбор
      cubit.prevDay();
      expect(cubit.state.selected, isEmpty);
      expect(cubit.state.rows, hasLength(1));

      // Выбор на предыдущем дне
      final prevRow = cubit.state.rows.first;
      cubit.toggleSelected(prevRow);
      expect(cubit.state.selected, {'${prevRow.app}|${prevRow.title}'});

      // Переход на следующий день сбрасывает выбор
      cubit.nextDay();
      expect(cubit.state.selected, isEmpty);

      // Проверка clearSelection
      final row1 = cubit.state.rows.first;
      cubit.toggleSelected(row1);
      expect(cubit.state.selected, isNotEmpty);
      cubit.clearSelection();
      expect(cubit.state.selected, isEmpty);

      cubit.close();
    });

    test('deleteSelected удаляет выбранное, сбрасывает выбор и обновляет rows', () async {
      final tracker = ActivityTracker(
        store: _MemStore(),
        inPomodoro: () => true,
      );
      final today = logicalDate(clock.now());
      final todayKey = dateKey(today);
      addTick(
        tracker.data.days.putIfAbsent(todayKey, () => {}),
        app: 'code.exe',
        seconds: 100,
        inFocus: true,
      );
      addTick(
        tracker.data.days.putIfAbsent(todayKey, () => {}),
        app: 'chrome.exe',
        title: 'Docs',
        seconds: 200,
        inFocus: false,
      );

      final cubit = ActivityCubit(tracker)..refresh();
      expect(cubit.state.rows, hasLength(2));

      final docRow = cubit.state.rows.firstWhere((r) => r.app == 'chrome.exe');
      cubit.toggleSelected(docRow);
      expect(cubit.state.selected, {'chrome.exe|Docs'});

      await cubit.deleteSelected(everywhere: false);

      expect(cubit.state.selected, isEmpty);
      expect(cubit.state.rows, hasLength(1));
      expect(cubit.state.rows.first.app, 'code.exe');
      expect(tracker.data.days[todayKey]!.containsKey('chrome.exe|Docs'), isFalse);

      await cubit.close();
    });
  });
}

/// Хранилище без диска: в тестах path_provider недоступен.
class _MemStore extends ActivityStore {
  @override
  Future<void> save(ActivityData data) async {}
}
