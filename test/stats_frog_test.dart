import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/presentation/cubits/stats_cubit.dart';

/// Мягкая стата лягушек: дней с 🐸 из активных дней. Без стрика —
/// «текущей серии» здесь нет намеренно.
void main() {
  DayLog day(int d, {int pomos = 0, bool frog = false}) => DayLog(
    date: DateTime(2026, 7, d),
    goal: 8,
    sessions: [
      for (var i = 0; i < pomos; i++)
        PomoSession(
          start: DateTime(2026, 7, d, 9 + i),
          minutes: 25,
          category: 'работа',
          task: 'X',
          // Лягушка — только первый помидор дня.
          frog: frog && i == 0,
        ),
    ],
  );

  StatsState stateWith(List<DayLog> days) => StatsState(
    status: StatsStatus.ready,
    period: StatsPeriod.week,
    periodDays: days,
    last14: days,
  );

  group('стата лягушек', () {
    test('считает дни с лягушкой и активные дни', () {
      final state = stateWith([
        day(13, pomos: 3, frog: true),
        day(14, pomos: 2), // работал, но лягушку не трогал
        day(15, pomos: 1, frog: true),
        day(16), // пустой день — не активный
      ]);
      expect(state.frogDays, 2);
      expect(state.activeDays, 3);
    });

    test('пустой период — нули, без деления на ноль', () {
      final state = stateWith([day(13), day(14)]);
      expect(state.frogDays, 0);
      expect(state.activeDays, 0);
    });

    test('день считается лягушачьим при любом 🐸-помидоре', () {
      expect(day(13, pomos: 3, frog: true).hasFrog, isTrue);
      expect(day(13, pomos: 3).hasFrog, isFalse);
    });
  });
}
