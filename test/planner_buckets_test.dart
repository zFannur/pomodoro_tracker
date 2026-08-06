import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';

/// Задача, запланированная «на завтра», назавтра проваливалась во «Входящие»
/// и терялась среди задач вообще без даты — пользователь читал это как
/// «просто пропала».
void main() {
  PomoTask task(DateTime? due) =>
      PomoTask(description: 'x', category: 'к', durationMinutes: 25, due: due);

  // Четверг.
  final now = DateTime(2026, 8, 6);

  test('«на завтра» лежит в «Завтра», пока завтра не наступило', () {
    final t = task(plannerDueFor(PlannerTab.tomorrow, now));
    expect(t.tab(now), PlannerTab.tomorrow);
  });

  test('назавтра та же задача попадает в «Пора», а не во «Входящие»', () {
    final t = task(plannerDueFor(PlannerTab.tomorrow, now));
    final tomorrow = DateTime(2026, 8, 7);
    expect(t.tab(tomorrow), PlannerTab.due);
  });

  test('просроченная задача тоже в «Пора»', () {
    final t = task(DateTime(2026, 8, 1));
    expect(t.tab(now), PlannerTab.due);
  });

  test('задача без срока остаётся во «Входящих»', () {
    expect(task(null).tab(now), PlannerTab.inbox);
  });

  test('каждая корзина классифицируется в саму себя', () {
    for (final tab in PlannerTab.values) {
      final due = plannerDueFor(tab, now);
      expect(
        task(due).tab(now),
        tab,
        reason: 'срок для «$tab» должен читаться обратно как «$tab»',
      );
    }
  });

  test('в воскресенье «позже» не совпадает с «завтра»', () {
    final sunday = DateTime(2026, 8, 9);
    expect(sunday.weekday, DateTime.sunday);
    final later = plannerDueFor(PlannerTab.later, sunday)!;
    final tomorrow = plannerDueFor(PlannerTab.tomorrow, sunday)!;
    expect(later.isAfter(tomorrow), isTrue);
    expect(task(later).tab(sunday), PlannerTab.later);
  });
}
