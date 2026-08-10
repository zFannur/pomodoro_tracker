import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/presentation/cubits/sprint_cubit.dart';

/// Разбор дня и недели: что попадает в списки «сделано».
void main() {
  PomoSession s(String task, {String category = 'кат', int minutes = 25}) =>
      PomoSession(
        id: '$task-$minutes',
        start: DateTime(2026, 8, 3, 10),
        minutes: minutes,
        category: category,
        task: task,
      );

  DayLog day(int d, List<PomoSession> sessions) =>
      DayLog(date: DateTime(2026, 8, d), goal: 10, sessions: sessions);

  test('строки недели собираются по всем дням', () {
    final lines = buildDoneLines([
      day(3, [s('отчёт')]),
      day(4, [s('синк', category: 'Uzum')]),
    ]);
    expect(lines, ['✅ 03.08 отчёт #кат', '✅ 04.08 синк #Uzum']);
  });

  test('явные отметки идут первыми и журналом не дублируются', () {
    final lines = buildDoneLines(
      [
        day(3, [s('отчёт'), s('отчёт')]),
      ],
      explicit: const ['✅ 03.08 отчёт #кат'],
    );
    expect(lines, ['✅ 03.08 отчёт #кат']);
  });

  test('запись без описания в список не попадает', () {
    expect(
      buildDoneLines([
        day(3, [s('   ')]),
      ]),
      isEmpty,
    );
  });

  test('понедельник восстанавливается по id недели', () {
    final monday = mondayOfSprintId('2026-W32');
    expect(monday, isNotNull);
    expect(monday!.weekday, DateTime.monday);
    expect(sprintId(monday), '2026-W32');
  });

  test('кривой id недели не ломает разбор', () {
    expect(mondayOfSprintId('мусор'), isNull);
    expect(mondayOfSprintId('2026-32'), isNull);
  });

  test('id недели переживает круг id → понедельник → id', () {
    for (final id in ['2026-W01', '2026-W29', '2026-W52', '2027-W10']) {
      expect(sprintId(mondayOfSprintId(id)!), id, reason: 'сломался на $id');
    }
  });
}
