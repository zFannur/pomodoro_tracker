import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/pomo_session.dart';
import '../../domain/repositories.dart';

enum StatsStatus { loading, ready, failure }

enum StatsPeriod { today, week, month, year, custom }

class StatsState extends Equatable {
  const StatsState({
    required this.status,
    required this.period,
    required this.periodDays,
    required this.last14,
    this.customFrom,
    this.customTo,
    this.streak = 0,
    this.goal = 0,
    this.error = '',
  });

  final StatsStatus status;
  final StatsPeriod period;

  /// Дни выбранного периода.
  final List<DayLog> periodDays;

  /// Последние 14 дней для графика.
  final List<DayLog> last14;
  final DateTime? customFrom;
  final DateTime? customTo;

  /// Дней подряд (включая сегодня, если есть помидоры) с ≥1 помидором.
  final int streak;
  final int goal;
  final String error;

  int get periodPomodoros => periodDays.fold(0, (sum, d) => sum + d.count);

  int get periodMinutes => periodDays.fold(0, (sum, d) => sum + d.minutes);

  /// Фокус за период — по формуле оригинала на агрегатах.
  int get periodFocus => focusPercent(
    amount: periodPomodoros,
    minutes: periodMinutes,
    delayMinutes: periodDays.fold(0, (sum, d) => sum + d.delayMinutes),
    interruptions: periodDays.fold(0, (sum, d) => sum + d.interruptions),
  );

  DayLog? get bestDay {
    DayLog? best;
    for (final d in periodDays) {
      if (d.count > 0 && (best == null || d.count > best.count)) best = d;
    }
    return best;
  }

  Map<String, int> get byCategory {
    final result = <String, int>{};
    for (final day in periodDays) {
      for (final s in day.sessions) {
        final name = s.category.isEmpty ? '—' : s.category;
        result[name] = (result[name] ?? 0) + 1;
      }
    }
    final entries = result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in entries) e.key: e.value};
  }

  StatsState copyWith({
    StatsStatus? status,
    StatsPeriod? period,
    List<DayLog>? periodDays,
    List<DayLog>? last14,
    DateTime? customFrom,
    DateTime? customTo,
    int? streak,
    int? goal,
    String? error,
  }) {
    return StatsState(
      status: status ?? this.status,
      period: period ?? this.period,
      periodDays: periodDays ?? this.periodDays,
      last14: last14 ?? this.last14,
      customFrom: customFrom ?? this.customFrom,
      customTo: customTo ?? this.customTo,
      streak: streak ?? this.streak,
      goal: goal ?? this.goal,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    period,
    periodDays,
    last14,
    customFrom,
    customTo,
    streak,
    goal,
    error,
  ];
}

class StatsCubit extends Cubit<StatsState> {
  StatsCubit(this._journal, this._dailyGoal)
    : super(
        const StatsState(
          status: StatsStatus.loading,
          period: StatsPeriod.today,
          periodDays: [],
          last14: [],
        ),
      );

  final JournalRepository _journal;
  final int Function() _dailyGoal;

  Future<void> setPeriod(
    StatsPeriod period, {
    DateTime? from,
    DateTime? to,
  }) async {
    emit(state.copyWith(period: period, customFrom: from, customTo: to));
    await refresh();
  }

  Future<void> refresh() async {
    final goal = _dailyGoal();
    final today = logicalDate(DateTime.now());
    final from = switch (state.period) {
      StatsPeriod.today => today,
      StatsPeriod.week => DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      ),
      StatsPeriod.month => DateTime(today.year, today.month),
      StatsPeriod.year => DateTime(today.year - 1, today.month, today.day + 1),
      StatsPeriod.custom => state.customFrom ?? today,
    };
    final to = state.period == StatsPeriod.custom
        ? (state.customTo ?? today)
        : today;
    // Хвост в 60 дней — для серии и графика 14 дней.
    final tail = DateTime(today.year, today.month, today.day - 59);
    final start = from.isBefore(tail) ? from : tail;
    final result = await _journal.range(
      start,
      to.isAfter(today) ? to : today,
      goal,
    );
    result.match(
      (failure) => emit(
        state.copyWith(status: StatsStatus.failure, error: failure.message),
      ),
      (days) {
        final periodDays = days
            .where((d) => !d.date.isBefore(from) && !d.date.isAfter(to))
            .toList(growable: false);
        final upToToday = days
            .where((d) => !d.date.isAfter(today))
            .toList(growable: false);
        final last14 = upToToday.length <= 14
            ? upToToday
            : upToToday.sublist(upToToday.length - 14);
        var streak = 0;
        for (var i = upToToday.length - 1; i >= 0; i--) {
          if (upToToday[i].count > 0) {
            streak++;
          } else if (i == upToToday.length - 1) {
            // Сегодня ещё без помидоров — серия не обнуляется.
            continue;
          } else {
            break;
          }
        }
        emit(
          state.copyWith(
            status: StatsStatus.ready,
            periodDays: periodDays,
            last14: last14,
            streak: streak,
            goal: goal,
          ),
        );
      },
    );
  }
}
