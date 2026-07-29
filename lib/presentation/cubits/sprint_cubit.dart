import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/markdown_codec.dart' show sprintId, two;
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/entities/sprint.dart';
import '../../domain/repositories.dart';

enum SprintStatus { loading, ready, failure }

class SprintState extends Equatable {
  const SprintState({
    required this.status,
    this.sprint,
    this.fact = const [],
    this.history = const [],
    this.error = '',
  });

  final SprintStatus status;
  final Sprint? sprint;

  /// Факт по дням недели (пн–вс).
  final List<DayLog> fact;
  final List<SprintSummary> history;
  final String error;

  /// Что сделано за неделю. Явные отметки о закрытых ⭐-задачах ПЛЮС всё,
  /// что реально попало в журнал.
  ///
  /// На одни ⭐ полагаться нельзя: список наполнялся только полностью
  /// закрытыми ⭐-задачами, а сами ⭐ снимаются при каждом переходе недели —
  /// чтобы сюда что-то попало, надо было заново отметить задачу звездой в
  /// понедельник и закрыть её целиком до воскресенья. На практике секция
  /// поэтому почти всегда пустовала.
  List<String> get doneLines {
    final result = <String>[...?sprint?.doneWeek];
    final seen = result.toSet();
    for (final day in fact) {
      for (final s in day.sessions) {
        final task = s.task.trim();
        if (task.isEmpty) continue;
        final line =
            '✅ ${two(day.date.day)}.${two(day.date.month)} $task'
            '${s.category.isEmpty ? '' : ' #${s.category}'}';
        if (seen.add(line)) result.add(line);
      }
    }
    return result;
  }

  int get factPomodoros => fact.fold(0, (sum, d) => sum + d.count);

  int get factMinutes => fact.fold(0, (sum, d) => sum + d.minutes);

  /// Средний темп по прошедшим дням недели.
  double get velocity {
    final today = logicalDate(DateTime.now());
    final passed = fact
        .where((d) => !d.date.isAfter(today))
        .toList(growable: false);
    if (passed.isEmpty) return 0;
    return factPomodoros / passed.length;
  }

  /// Прогноз на конец недели при текущем темпе.
  int get forecast => (velocity * 7).round();

  SprintState copyWith({
    SprintStatus? status,
    Sprint? sprint,
    List<DayLog>? fact,
    List<SprintSummary>? history,
    String? error,
  }) {
    return SprintState(
      status: status ?? this.status,
      sprint: sprint ?? this.sprint,
      fact: fact ?? this.fact,
      history: history ?? this.history,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, sprint, fact, history, error];
}

/// Неделя: веха + цель в помидорах. Задачи недели живут в общем списке
/// задач с меткой ⭐ — сюда попадают их снапшот и «Сделано за неделю».
class SprintCubit extends Cubit<SprintState> {
  SprintCubit(
    this._sprints,
    this._journal,
    this._defaultGoal,
    this._dailyGoal,
    this._weekTasks,
  ) : super(const SprintState(status: SprintStatus.loading));

  final SprintRepository _sprints;
  final JournalRepository _journal;
  final int Function() _defaultGoal;
  final int Function() _dailyGoal;

  /// ⭐-задачи из общего списка (Сегодня + Планировщик).
  final List<PomoTask> Function() _weekTasks;

  Future<void> refresh() async {
    // Логический день (05:00): в ночь на понедельник неделя ещё старая.
    final now = logicalDate(DateTime.now());
    final result = await _sprints.current(now, _defaultGoal());
    await result.match(
      (failure) async => emit(
        state.copyWith(status: SprintStatus.failure, error: failure.message),
      ),
      (sprint) async {
        final factResult = await _journal.range(
          sprint.start,
          sprint.end,
          _dailyGoal(),
        );
        await factResult.match(
          (failure) async => emit(
            state.copyWith(
              status: SprintStatus.failure,
              error: failure.message,
            ),
          ),
          (fact) async {
            final historyResult = await _sprints.history();
            final history = historyResult.getOrElse((_) => state.history);
            emit(
              state.copyWith(
                status: SprintStatus.ready,
                sprint: sprint,
                fact: fact,
                history: history,
              ),
            );
            await _sprints.saveSprint(sprint, fact, weekTasks: _weekTasks());
          },
        );
      },
    );
  }

  Future<void> setGoal(int goal) async {
    final sprint = state.sprint;
    if (sprint == null || goal <= 0) return;
    await _save(sprint.copyWith(goal: goal));
  }

  Future<void> setMilestone(String milestone) async {
    final sprint = state.sprint;
    if (sprint == null) return;
    await _save(sprint.copyWith(milestone: milestone.trim()));
  }

  /// Закрытая ⭐-задача уезжает в «Сделано за неделю».
  Future<void> addDoneWeek(String line) async {
    // Убеждаемся, что в руках спринт ТЕКУЩЕЙ недели. Раньше бралось то, что
    // лежало в state: после перехода недели закрытие уезжало в прошлую, а
    // если спринт ещё не загрузился — строка просто терялась.
    final id = sprintId(logicalDate(DateTime.now()));
    if (state.sprint?.id != id) await refresh();
    final sprint = state.sprint;
    if (sprint == null || sprint.doneWeek.contains(line)) return;
    await _save(sprint.copyWith(doneWeek: [...sprint.doneWeek, line]));
  }

  Future<void> _save(Sprint sprint) async {
    emit(state.copyWith(status: SprintStatus.ready, sprint: sprint));
    final result = await _sprints.saveSprint(
      sprint,
      state.fact,
      weekTasks: _weekTasks(),
    );
    result.match(
      (failure) => emit(
        state.copyWith(status: SprintStatus.failure, error: failure.message),
      ),
      (_) {},
    );
  }
}
