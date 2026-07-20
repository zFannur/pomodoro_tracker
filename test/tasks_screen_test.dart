import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/presentation/screens/sprint_screen.dart';
import 'package:pomodoro_tracker/presentation/screens/tasks_screen.dart';

import 'screen_fakes.dart';

/// Экраны «Задачи» и «Спринт» на телефонной и на широкой ширине.
/// Ловим две разные беды: выход за край (RenderFlex ругается сам) и
/// зажатый до нечитаемого текст (о нём никто не ругается — меряем).
void main() {
  const phone = Size(411, 850);
  const desktop = Size(1280, 900);

  testWidgets('«Задачи» строятся на телефоне', (tester) async {
    final h = await pumpScreen(tester, phone, const TasksScreen());
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('«Задачи» строятся на широком экране', (tester) async {
    final h = await pumpScreen(tester, desktop, const TasksScreen());
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('на «Задачах» описаниям достаётся ширина', (tester) async {
    final h = await pumpScreen(tester, phone, const TasksScreen());
    for (final text in const [kLongTodo, kLongPlanned]) {
      final width = rowTextWidth(tester, text);
      // Порог сторожит возврат к патологии (было ~40dp — буквы в столбик),
      // а не идеальную вёрстку.
      expect(
        width,
        greaterThan(phone.width * 0.4),
        reason: 'описанию «$text» осталось ${width.round()}dp',
      );
    }
    await h.dispose();
  });

  testWidgets('«Спринт» строится на телефоне', (tester) async {
    final h = await pumpScreen(tester, phone, const SprintScreen());
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('«Спринт» строится на широком экране', (tester) async {
    final h = await pumpScreen(tester, desktop, const SprintScreen());
    expect(tester.takeException(), isNull);
    await h.dispose();
  });
}
