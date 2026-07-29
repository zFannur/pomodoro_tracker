import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/presentation/cubits/sprint_cubit.dart';

/// «Сделано за неделю» раньше наполнялось только полностью закрытыми
/// ⭐-задачами, а ⭐ снимаются при каждом переходе недели — секция пустовала
/// практически всегда.
void main() {
  PomoSession s(String task, {String category = 'кат'}) => PomoSession(
    id: task,
    start: DateTime(2026, 7, 20, 10),
    minutes: 25,
    category: category,
    task: task,
  );

  DayLog day(int d, List<PomoSession> sessions) =>
      DayLog(date: DateTime(2026, 7, d), goal: 10, sessions: sessions);

  test('строки берутся из журнала, а не только из ⭐-закрытий', () {
    const state = SprintState(status: SprintStatus.ready);
    final filled = state.copyWith(
      sprint: Sprint(id: '2026-W30', start: DateTime(2026, 7, 20), goal: 40),
      fact: [
        day(20, [s('написать отчёт')]),
        day(21, [s('починить синк', category: 'Uzum')]),
      ],
    );
    expect(filled.doneLines, [
      '✅ 20.07 написать отчёт #кат',
      '✅ 21.07 починить синк #Uzum',
    ]);
  });

  test('явные ⭐-отметки идут первыми и не дублируются журналом', () {
    const state = SprintState(status: SprintStatus.ready);
    final filled = state.copyWith(
      sprint: Sprint(
        id: '2026-W30',
        start: DateTime(2026, 7, 20),
        goal: 40,
        doneWeek: const ['✅ 20.07 написать отчёт #кат'],
      ),
      fact: [
        day(20, [s('написать отчёт'), s('написать отчёт')]),
      ],
    );
    expect(filled.doneLines, ['✅ 20.07 написать отчёт #кат']);
  });

  test('пустая неделя даёт пустой список, а не падение', () {
    const state = SprintState(status: SprintStatus.ready);
    expect(state.doneLines, isEmpty);
  });

  test('запись без описания задачи в список не попадает', () {
    const state = SprintState(status: SprintStatus.ready);
    final filled = state.copyWith(
      fact: [
        day(20, [s('  ')]),
      ],
    );
    expect(filled.doneLines, isEmpty);
  });
}
