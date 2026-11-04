import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/insights.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

/// Хранилище без диска: запоминает последний сохранённый снимок.
class _MemStore extends ActivityStore {
  _MemStore([this.initial]);

  final ActivityData? initial;
  ActivityData? saved;

  @override
  Future<ActivityData> load() async => initial ?? ActivityData();

  @override
  Future<void> save(ActivityData data) async => saved = data;
}

ActivitySegment _seg(DateTime from, int minutes, String app, [String t = '']) =>
    ActivitySegment(
      from: from,
      to: from.add(Duration(minutes: minutes)),
      app: app,
      title: t,
    );

/// Типичные окна дня: редактор, вкладки браузера (рус./англ. заголовки
/// обычной длины), мессенджер, проводник.
const _windows = [
  (exe: 'code.exe', title: 'main.dart - pomodoro_tracker - Visual Studio Code'),
  (exe: 'chrome.exe', title: 'YouTube - Google Chrome'),
  (
    exe: 'chrome.exe',
    title: 'Как подключить webhook Stripe к Flutter-приложению — Хабр - Google Chrome',
  ),
  (exe: 'telegram.exe', title: 'Telegram'),
  (
    exe: 'chrome.exe',
    title: 'flutter_bloc | Flutter package - pub.dev - Google Chrome',
  ),
  (exe: 'explorer.exe', title: 'Загрузки'),
  (
    exe: 'msedge.exe',
    title: 'Входящие (12) - почта@example.ru - Яндекс Почта - Microsoft​ Edge',
  ),
  (exe: 'obsidian.exe', title: 'Журнал - Obsidian'),
];

/// Прогоняет трекер [hours] часов вне помидора, окно меняется каждые
/// [switchSeconds] секунд по кругу из [windows]. Возвращает размер JSON
/// одного дня `idle` в байтах UTF-8.
int _idleDayBytes(
  List<({String exe, String title})> windows, {
  int hours = 8,
  int switchSeconds = 30,
}) {
  late int bytes;
  fakeAsync((async) {
    var i = 0;
    final tracker = ActivityTracker(
      store: _MemStore(),
      inPomodoro: () => false,
      inputIdleReader: () => 0,
      foregroundReader: () => windows[i % windows.length],
    );
    final ticksPerWindow = switchSeconds ~/ activityTickSeconds;
    final total = hours * 3600 ~/ activityTickSeconds;
    for (var t = 0; t < total; t++) {
      async.elapse(const Duration(seconds: activityTickSeconds));
      tracker.poll();
      if ((t + 1) % ticksPerWindow == 0) i++;
    }
    final idle = tracker.data.toJson()['idle'] as Map<String, dynamic>;
    expect(idle.keys, ['2026-11-04']);
    expect(
      tracker.data.idleSegments['2026-11-04'],
      hasLength(total ~/ ticksPerWindow),
    );
    bytes = utf8.encode(jsonEncode(idle['2026-11-04'])).length;
    unawaited(tracker.dispose());
    async.flushMicrotasks();
  }, initialTime: DateTime(2026, 11, 4, 9));
  return bytes;
}

void main() {
  group('idleSegments в трекере', () {
    test('вне помидора пишутся в idle, в помидоре — в segments', () {
      fakeAsync((async) {
        var inFocus = false;
        final tracker = ActivityTracker(
          store: _MemStore(),
          inPomodoro: () => inFocus,
          inputIdleReader: () => 0,
          foregroundReader: () => (exe: 'telegram.exe', title: ''),
        );
        void ticks(int n) {
          for (var i = 0; i < n; i++) {
            async.elapse(const Duration(seconds: 5));
            tracker.poll();
          }
        }

        ticks(6);
        expect(tracker.data.focusSegments, isEmpty);
        final idle = tracker.data.idleSegments['2026-11-04']!;
        expect(idle, hasLength(1));
        expect(idle.single.app, 'telegram.exe');
        expect(idle.single.to.difference(idle.single.from).inSeconds, 30);

        inFocus = true;
        ticks(4);
        expect(tracker.data.idleSegments['2026-11-04'], hasLength(1));
        expect(
          tracker.data.idleSegments['2026-11-04']!.single.to,
          DateTime(2026, 11, 4, 10, 0, 30),
        );
        expect(tracker.data.focusSegments['2026-11-04'], hasLength(1));

        // Отошёл от компьютера — не пишется никуда.
        final away = ActivityTracker(
          store: _MemStore(),
          inPomodoro: () => false,
          inputIdleReader: () => 500,
          foregroundReader: () => (exe: 'telegram.exe', title: ''),
        );
        async.elapse(const Duration(seconds: 5));
        away.poll();
        expect(away.data.idleSegments, isEmpty);

        unawaited(tracker.dispose());
        unawaited(away.dispose());
        async.flushMicrotasks();
      }, initialTime: DateTime(2026, 11, 4, 10));
    });

    test('start и flush хранят idle 14 дней, а segments — 60', () {
      final initial = ActivityData();
      for (final key in ['2026-11-04', '2026-10-22', '2026-10-21', '2026-09-06']) {
        final d = DateTime.parse(key).add(const Duration(hours: 10));
        initial.idleSegments[key] = [_seg(d, 5, 'a.exe')];
        initial.focusSegments[key] = [_seg(d, 5, 'a.exe')];
      }
      final store = _MemStore(initial);
      fakeAsync((async) {
        final tracker = ActivityTracker(
          store: store,
          inPomodoro: () => false,
          inputIdleReader: () => 0,
          foregroundReader: () => (exe: 'b.exe', title: ''),
        );
        unawaited(tracker.start());
        async.flushMicrotasks();
        // Вне Windows start — no-op: данные подставляем сами, чистку
        // проверяет flush.
        tracker.data = initial;
        async.elapse(const Duration(seconds: 5));
        tracker.poll();
        unawaited(tracker.flush());
        async.flushMicrotasks();
        expect(store.saved, isNotNull);
        expect(
          store.saved!.idleSegments.keys,
          unorderedEquals(['2026-11-04', '2026-10-22']),
        );
        expect(
          store.saved!.focusSegments.keys,
          unorderedEquals(['2026-11-04', '2026-10-22', '2026-10-21', '2026-09-06']),
        );
        unawaited(tracker.dispose());
        async.flushMicrotasks();
      }, initialTime: DateTime(2026, 11, 4, 10));
    });

    test('pruneDays(keep: 14): 14-й день остаётся, 15-й удаляется', () {
      final days = <String, List<ActivitySegment>>{
        '2026-11-04': [],
        '2026-10-22': [],
        '2026-10-21': [],
      };
      pruneDays(days, DateTime(2026, 11, 4), keep: keepIdleDays);
      expect(days.keys, unorderedEquals(['2026-11-04', '2026-10-22']));
    });
  });

  group('idleSegments в JSON', () {
    test('туда-обратно; idle не становится днём', () {
      final data = ActivityData();
      final t = DateTime(2026, 11, 4, 10);
      data.idleSegments['2026-11-04'] = [_seg(t, 5, 'chrome.exe', 'YouTube')];
      data.focusSegments['2026-11-04'] = [_seg(t, 25, 'code.exe')];
      final json = jsonDecode(jsonEncode(data.toJson()));
      final copy = ActivityData.fromJson(json);
      expect(copy.idleSegments['2026-11-04'], data.idleSegments['2026-11-04']);
      expect(copy.focusSegments['2026-11-04'], data.focusSegments['2026-11-04']);
      expect(copy.days.keys, isNot(contains('idle')));
      expect(copy.days, isEmpty);
    });

    test('пустой idle в JSON не пишется', () {
      expect(ActivityData().toJson().containsKey('idle'), isFalse);
    });

    test('старый файл без idle читается', () {
      final data = ActivityData.fromJson({
        '2026-10-05': [
          {'app': 'code.exe', 'title': '', 'seconds': 60, 'focusSeconds': 60},
        ],
        'segments': <String, dynamic>{},
        'distracting': ['code.exe'],
      });
      expect(data.idleSegments, isEmpty);
      expect(data.days['2026-10-05']!['code.exe|']!.seconds, 60);
      expect(data.distracting, {'code.exe'});
    });

    test('битый idle пропускается, остальное читается', () {
      final data = ActivityData.fromJson({
        'idle': {
          '2026-11-04': [
            {'from': 'x', 'to': 'y', 'app': 'a.exe'},
            _seg(DateTime(2026, 11, 4, 10), 1, 'b.exe').toJson(),
          ],
          '2026-11-03': 'мусор',
        },
        '2026-11-04': [
          {'app': 'b.exe', 'seconds': 60},
        ],
      });
      expect(data.idleSegments.keys, ['2026-11-04']);
      expect(data.idleSegments['2026-11-04']!.single.app, 'b.exe');
      expect(data.days.keys, ['2026-11-04']);
      expect(ActivityData.fromJson({'idle': 'мусор'}).days, isEmpty);
    });
  });

  group('удаление истории', () {
    test('за день и за все дни чистит idleSegments', () {
      final data = ActivityData();
      final t1 = DateTime(2026, 11, 3, 10);
      final t2 = DateTime(2026, 11, 4, 10);
      data.idleSegments['2026-11-03'] = [
        _seg(t1, 5, 'chrome.exe', 'YouTube'),
        _seg(t1, 5, 'code.exe'),
      ];
      data.idleSegments['2026-11-04'] = [_seg(t2, 5, 'chrome.exe', 'YouTube')];
      const yt = (app: 'chrome.exe', title: 'YouTube');

      deleteActivity(data, {yt}, day: '2026-11-04');
      expect(data.idleSegments.containsKey('2026-11-04'), isFalse);
      expect(data.idleSegments['2026-11-03'], hasLength(2));

      data.idleSegments['2026-11-04'] = [_seg(t2, 5, 'chrome.exe', 'YouTube')];
      deleteActivity(data, {yt});
      expect(data.idleSegments.keys, ['2026-11-03']);
      expect(data.idleSegments['2026-11-03']!.single.app, 'code.exe');
    });

    test('день только с idle тоже попадает в «все дни»', () {
      final data = ActivityData();
      data.idleSegments['2026-11-01'] = [
        _seg(DateTime(2026, 11, 1, 10), 5, 'game.exe'),
      ];
      deleteActivity(data, {(app: 'game.exe', title: '')});
      expect(data.idleSegments, isEmpty);
    });

    test('ActivityCubit.deleteRow чистит idle', () async {
      final tracker = ActivityTracker(store: _MemStore(), inPomodoro: () => false);
      final cubit = ActivityCubit(tracker);
      tracker.data.idleSegments['2026-11-01'] = [
        _seg(DateTime(2026, 11, 1, 10), 5, 'game.exe'),
      ];
      final row = (
        key: 'game.exe',
        app: 'game.exe',
        title: '',
        seconds: 300,
        focusSeconds: 0,
      );
      await cubit.deleteRow(row, everywhere: true);
      expect(tracker.data.idleSegments, isEmpty);
      await cubit.close();
    });
  });

  group('размер дня idle', () {
    test('8 часов, окно каждые 30 с: JSON дня < 300 КБ', () {
      final bytes = _idleDayBytes(_windows);
      // ignore: avoid_print
      print('idle: 8 ч, смена окна каждые 30 с — ${(bytes / 1024).toStringAsFixed(1)} КБ');
      expect(bytes, lessThan(300 * 1024));
    });

    test('худший случай: заголовки по 120 кириллических символов (замер)', () {
      final long = 'Ж' * 150;
      final windows = [
        for (var i = 0; i < 8; i++)
          (exe: 'chrome.exe', title: '$i$long - Google Chrome'),
      ];
      final bytes = _idleDayBytes(windows);
      // ignore: avoid_print
      print('idle: худший случай — ${(bytes / 1024).toStringAsFixed(1)} КБ');
      expect(bytes, greaterThan(0));
    });
  });

  group('insteadWindow', () {
    final at = DateTime(2026, 11, 4, 10);
    Episode ep(EpisodeSource? source) =>
        Episode(id: 'e', at: at, source: source);
    PomoSession pomo(DateTime start, {bool manual = false}) => PomoSession(
      id: '${start.millisecondsSinceEpoch}',
      start: start,
      minutes: 25,
      category: 'work',
      task: 'Задача',
      manual: manual,
    );

    test('ближайший помидор через 20 мин → от −15 до +20 мин', () {
      final w = insteadWindow(ep(EpisodeSource.idle), [
        pomo(at.subtract(const Duration(hours: 1))),
        pomo(at.add(const Duration(minutes: 40))),
        pomo(at.add(const Duration(minutes: 20))),
      ])!;
      expect(w.from, at.subtract(const Duration(minutes: 15)));
      expect(w.to, at.add(const Duration(minutes: 20)));
    });

    test('помидора нет (или он позже часа, или ручной) → 60 мин', () {
      for (final sessions in [
        <PomoSession>[],
        [pomo(at.add(const Duration(minutes: 90)))],
        [pomo(at.add(const Duration(minutes: 10)), manual: true)],
      ]) {
        final w = insteadWindow(ep(EpisodeSource.manual), sessions)!;
        expect(w.from, at.subtract(const Duration(minutes: 15)));
        expect(w.to, at.add(const Duration(minutes: 60)));
      }
    });

    test('defer — тоже окно; stop, distract, frog, неизвестный — null', () {
      expect(insteadWindow(ep(EpisodeSource.defer), const []), isNotNull);
      for (final s in [
        EpisodeSource.stop,
        EpisodeSource.distract,
        EpisodeSource.frog,
        null,
      ]) {
        expect(insteadWindow(ep(s), const []), isNull, reason: '$s');
      }
    });
  });

  group('segmentsForWindows', () {
    test('пересекающиеся окна не считают отрезок дважды', () {
      final t = DateTime(2026, 11, 4, 10);
      final byDay = {
        '2026-11-04': [_seg(t, 30, 'chrome.exe', 'YouTube')],
      };
      final rows = segmentsForWindows(byDay, [
        (from: t, to: t.add(const Duration(minutes: 20))),
        (
          from: t.add(const Duration(minutes: 10)),
          to: t.add(const Duration(minutes: 30)),
        ),
        // Вне отрезков и пустое окно — ничего не добавляют.
        (
          from: t.add(const Duration(hours: 2)),
          to: t.add(const Duration(hours: 2)),
        ),
      ]);
      expect(rows.single.title, 'YouTube');
      expect(rows.single.seconds, 30 * 60);
    });

    test('окно через 05:00 берёт отрезки обоих логических дней', () {
      final before = DateTime(2026, 11, 5, 4, 50);
      final after = DateTime(2026, 11, 5, 5, 0);
      final rows = segmentsForWindows(
        {
          '2026-11-04': [_seg(before, 10, 'a.exe')],
          '2026-11-05': [_seg(after, 10, 'b.exe')],
        },
        [(from: before, to: after.add(const Duration(minutes: 10)))],
      );
      expect({for (final r in rows) r.app: r.seconds}, {
        'a.exe': 600,
        'b.exe': 600,
      });
    });

    test('ActivityCubit.idleFor читает idle, а не segments', () async {
      final tracker = ActivityTracker(store: _MemStore(), inPomodoro: () => false);
      final t = DateTime(2026, 11, 4, 10);
      tracker.data.idleSegments['2026-11-04'] = [_seg(t, 5, 'game.exe')];
      tracker.data.focusSegments['2026-11-04'] = [_seg(t, 5, 'code.exe')];
      final cubit = ActivityCubit(tracker);
      final rows = cubit.idleFor([(from: t, to: t.add(const Duration(hours: 1)))]);
      expect(rows.single.app, 'game.exe');
      await cubit.close();
    });
  });
}
