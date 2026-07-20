import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/stats_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/stats_screen.dart';

/// Журнал в памяти: несколько дней с помидорами, чтобы отрисовались все блоки.
class _MemJournal implements JournalRepository {
  @override
  Future<Either<Failure, Unit>> addSession(PomoSession s, int goal) async =>
      Either.right(unit);

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) async => Either.right(unit);

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int goal) async =>
      Either.right(_day(date, goal));

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int goal,
  ) async {
    final days = <DayLog>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    while (!cursor.isAfter(last)) {
      days.add(_day(cursor, goal));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return Either.right(days);
  }

  DayLog _day(DateTime date, int goal) => DayLog(
    date: date,
    goal: goal,
    sessions: [
      for (var i = 0; i < 2; i++)
        PomoSession(
          id: '${date.day}-$i',
          start: DateTime(date.year, date.month, date.day, 9 + i),
          minutes: 25,
          category: 'работа',
          task: 'задача',
          frog: i == 0,
        ),
    ],
  );
}

void main() {
  /// Экран статистики уже ломался целиком из-за одного растягивания в ряду
  /// плиток: внутри прокручиваемой колонки высота не ограничена, и раскладка
  /// получала бесконечность. Глазами это ловится только вручную на двух
  /// ширинах, поэтому проверяем обе.
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = StatsCubit(_MemJournal(), () => 8);
    addTearDown(cubit.close);
    await cubit.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: StatsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('статистика строится на телефоне', (tester) async {
    await pumpAt(tester, const Size(411, 850));
    expect(tester.takeException(), isNull);
    expect(find.byType(StatsScreen), findsOneWidget);
  });

  testWidgets('статистика строится на широком экране', (tester) async {
    await pumpAt(tester, const Size(1280, 900));
    expect(tester.takeException(), isNull);
    expect(find.byType(StatsScreen), findsOneWidget);
  });
}
