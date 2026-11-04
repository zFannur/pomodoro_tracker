import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/data/activity_store.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/activity_cubit.dart';
import 'package:pomodoro_tracker/presentation/widgets/common.dart';
import 'package:pomodoro_tracker/presentation/widgets/windows_dialog.dart';
import 'package:pomodoro_tracker/services/activity_tracker.dart';

import 'screen_fakes.dart';

class _MemStore extends ActivityStore {
  @override
  Future<ActivityData> load() async => ActivityData();

  @override
  Future<void> save(ActivityData data) async {}
}

ActivityRow _row(String app, String title, int seconds) => (
  key: title.isEmpty ? app : title,
  app: app,
  title: title,
  seconds: seconds,
  focusSeconds: seconds,
);

final _start = DateTime(2026, 11, 3, 10);

PomoSession _session({String id = 's1', DateTime? start}) => PomoSession(
  id: id,
  start: start ?? _start,
  minutes: 25,
  category: 'work',
  task: 'Задача',
);

/// Открывает диалог кнопкой: у диалога свой маршрут, ему нужен живой context.
Future<ActivityCubit> _pumpDialog(
  WidgetTester tester, {
  required List<ActivityRow> Function(ActivityCubit cubit) rows,
  String empty = '',
  Size size = const Size(1000, 1500),
  ActivityTracker? tracker,
  List<({String label, List<ActivityRow> rows})> Function()? breakdown,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cubit = ActivityCubit(
    tracker ?? ActivityTracker(store: _MemStore(), inPomodoro: () => false),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWindowsDialog(
                context,
                title: 'Моя задача',
                subtitle: 'подзаголовок',
                rows: () => rows(cubit),
                breakdown: breakdown,
                empty: empty,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  testWidgets('флажок вызывает toggleDistracting, диалог перестраивается', (
    tester,
  ) async {
    final tracker = ActivityTracker(
      store: _MemStore(),
      inPomodoro: () => false,
    );
    tracker.data.focusSegments['2026-11-03'] = [
      ActivitySegment(
        from: _start,
        to: _start.add(const Duration(minutes: 20)),
        app: 'code.exe',
      ),
      ActivitySegment(
        from: _start.add(const Duration(minutes: 20)),
        to: _start.add(const Duration(minutes: 25)),
        app: 'chrome.exe',
        title: 'YouTube',
      ),
    ];
    await _pumpDialog(
      tester,
      tracker: tracker,
      rows: (cubit) => cubit.segmentsFor(_session()),
    );

    expect(find.text('Моя задача'), findsOneWidget);
    expect(find.text('подзаголовок'), findsOneWidget);
    expect(find.text('Chrome: YouTube'), findsOneWidget);
    expect(find.text('code'), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsNWidgets(2));
    expect(find.text(S.windowsDistractions(0)), findsOneWidget);

    // YouTube — вторая строка (меньше времени).
    await tester.tap(find.byIcon(Icons.flag_outlined).last);
    await tester.pumpAndSettle();

    expect(tracker.data.distracting, {'YouTube'});
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.text(S.windowsDistractions(20)), findsOneWidget);
    expect(find.text(S.windowsWork(80)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flag));
    await tester.pumpAndSettle();
    expect(tracker.data.distracting, isEmpty);
    expect(find.byIcon(Icons.flag), findsNothing);
  });

  testWidgets('15 строк: 12 сразу, «Ещё 3» раскрывает остальные', (
    tester,
  ) async {
    final rows = [for (var i = 0; i < 15; i++) _row('app$i.exe', '', 900 - i)];
    await _pumpDialog(tester, rows: (_) => rows);

    expect(find.byIcon(Icons.flag_outlined), findsNWidgets(12));
    expect(find.text('app11'), findsOneWidget);
    expect(find.text('app12'), findsNothing);

    await tester.ensureVisible(find.text(S.windowsMore(3)));
    await tester.tap(find.text(S.windowsMore(3)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.flag_outlined), findsNWidgets(15));
    expect(find.text('app14'), findsOneWidget);
    expect(find.text(S.windowsMore(3)), findsNothing);
  });

  testWidgets('12 строк ровно: кнопки «Ещё» нет', (tester) async {
    final rows = [for (var i = 0; i < 12; i++) _row('app$i.exe', '', 900 - i)];
    await _pumpDialog(tester, rows: (_) => rows);
    expect(find.byIcon(Icons.flag_outlined), findsNWidgets(12));
    expect(find.textContaining(S.windowsMore(0).split(' ').first), findsNothing);
  });

  testWidgets('«По помидорам»: свёрнуто, раскрывается, топ-3 окон', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      rows: (_) => [_row('code.exe', '', 1200)],
      breakdown: () => [
        (
          label: 'Вт 10:15 · 25 мин',
          rows: [
            _row('code.exe', '', 18 * 60),
            _row('chrome.exe', 'docs', 5 * 60),
            _row('telegram.exe', '', 2 * 60),
            _row('slack.exe', '', 60),
          ],
        ),
      ],
    );
    const line =
        'Вт 10:15 · 25 мин — code 18 мин, Chrome: docs 5 мин, telegram 2 мин';
    expect(find.text(S.windowsBySession), findsOneWidget);
    expect(find.text(line), findsNothing);
    await tester.tap(find.text(S.windowsBySession));
    await tester.pumpAndSettle();
    expect(find.text(line), findsOneWidget);
  });

  testWidgets('пустое состояние: свой текст и серая заметка про Windows', (
    tester,
  ) async {
    await _pumpDialog(tester, rows: (_) => [], empty: 'Нет помидоров');
    expect(find.text('Нет помидоров'), findsOneWidget);
    expect(find.text(S.windowsTrackerNote), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });

  testWidgets('пустое состояние без текста — S.sessionActivityEmpty', (
    tester,
  ) async {
    await _pumpDialog(tester, rows: (_) => []);
    expect(find.text(S.sessionActivityEmpty), findsOneWidget);
    expect(find.text(S.windowsTrackerNote), findsOneWidget);
  });

  testWidgets('узкий экран: диалог во весь экран, закрывается крестиком', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      rows: (_) => [_row('code.exe', '', 600)],
      size: const Size(400, 800),
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('code'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
  });

  group('пункт «Окна задачи» в TaskMenu', () {
    final task = PomoTask(
      id: 't9',
      description: 'Подключить webhook',
      category: 'work',
      durationMinutes: 25,
    );

    Future<Future<void> Function()> openMenu(
      WidgetTester tester, {
      required bool? isWindows,
      required bool withActivity,
    }) async {
      final activity = ActivityCubit(
        ActivityTracker(store: _MemStore(), inPomodoro: () => false),
      );
      final menu = TaskMenu(task: task, isWindows: isWindows);
      final h = await pumpScreen(
        tester,
        const Size(1000, 900),
        withActivity ? BlocProvider.value(value: activity, child: menu) : menu,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      // Закрыть до конца теста: JournalCubit держит таймер.
      return () async {
        await h.dispose();
        await tester.runAsync(activity.close);
      };
    }

    testWidgets('не Windows — пункта нет', (tester) async {
      final done = await openMenu(
        tester,
        isWindows: false,
        withActivity: true,
      );
      expect(find.text(S.menuMerge), findsOneWidget);
      expect(find.text(S.menuTaskWindows), findsNothing);
      await done();
    });

    testWidgets('Windows, но без ActivityCubit — пункта нет', (tester) async {
      final done = await openMenu(
        tester,
        isWindows: true,
        withActivity: false,
      );
      expect(find.text(S.menuMerge), findsOneWidget);
      expect(find.text(S.menuTaskWindows), findsNothing);
      await done();
    });

    testWidgets('Windows с трекером: пункт открывает диалог задачи', (
      tester,
    ) async {
      final done = await openMenu(
        tester,
        isWindows: true,
        withActivity: true,
      );
      await tester.tap(find.text(S.menuTaskWindows));
      await tester.pumpAndSettle();
      expect(find.text('Подключить webhook'), findsOneWidget);
      // У задачи нет помидоров (в журнале фейка только ручные отметки).
      expect(find.text(S.windowsNoPomos), findsOneWidget);
      await done();
    });
  });
}
