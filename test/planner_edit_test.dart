import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/planner_dialog.dart';
import 'package:pomodoro_tracker/presentation/screens/tasks_screen.dart';
import 'package:pomodoro_tracker/presentation/widgets/first_step_field.dart';

import 'screen_fakes.dart';

void main() {
  testWidgets('редактор корзины сохраняет изменения после обновления задачи', (
    tester,
  ) async {
    final harness = await pumpScreen(
      tester,
      const Size(1280, 900),
      const TasksScreen(),
    );
    final tasks = tester.element(find.byType(TasksScreen)).read<TasksCubit>();
    await tester.tap(find.text(kLongPlanned));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, S.descriptionHint),
      ),
      'Новое описание',
    );
    await tester.tap(find.text(S.startPlan));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(FirstStepField),
        matching: find.byType(TextField),
      ),
      'Первый шаг',
    );
    await tasks.setPlan('p1', cue: 'после завтрака');
    await tester.pump();
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();
    expect(tasks.state.planner.first.description, 'Новое описание');
    expect(tasks.state.planner.first.firstStep, 'Первый шаг');
    await harness.dispose();
  });

  testWidgets('редактор задачи планировщика сохраняет описание и план', (
    tester,
  ) async {
    final harness = await pumpScreen(
      tester,
      const Size(1280, 900),
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showPlannerDialog(context),
          child: const Text('Открыть планировщик'),
        ),
      ),
    );
    final tasks = tester
        .element(find.text('Открыть планировщик'))
        .read<TasksCubit>();
    await tester.tap(find.text('Открыть планировщик'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('${S.inbox} ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kLongPlanned));
    await tester.pumpAndSettle();
    expect(find.text(S.editTask), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, S.descriptionHint),
      ),
      'Новое описание',
    );
    await tester.tap(find.text(S.startPlan));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(FirstStepField),
        matching: find.byType(TextField),
      ),
      'Первый шаг',
    );
    await tester.tap(find.text(S.save));
    await tester.pumpAndSettle();
    expect(tasks.state.planner.first.description, 'Новое описание');
    expect(tasks.state.planner.first.firstStep, 'Первый шаг');
    await harness.dispose();
  });
}
