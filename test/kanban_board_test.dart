import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/presentation/widgets/kanban_board.dart';

import 'screen_fakes.dart';

void main() {
  testWidgets('карточки можно добавлять в конец непустой колонки', (
    tester,
  ) async {
    final harness = await pumpScreen(
      tester,
      const Size(1400, 900),
      const SingleChildScrollView(child: KanbanBoard()),
    );

    Future<void> moveToWorking(String text) async {
      final target = find.byKey(const ValueKey('kanban-drop-working-end'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.textContaining(text).first),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await moveToWorking(kLongTodo);
    expect(
      find.byKey(const ValueKey('kanban-drop-working-t1')),
      findsOneWidget,
    );

    final end = find.byKey(const ValueKey('kanban-drop-working-end'));
    expect(tester.getSize(end).height, greaterThanOrEqualTo(80));
    await moveToWorking(kLongPlanned);
    expect(
      find.byKey(const ValueKey('kanban-drop-working-p1')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.textContaining(kLongTodo).first).dy,
      lessThan(tester.getTopLeft(find.textContaining(kLongPlanned).first).dy),
    );
    expect(tester.takeException(), isNull);
    await harness.dispose();
  });
}
