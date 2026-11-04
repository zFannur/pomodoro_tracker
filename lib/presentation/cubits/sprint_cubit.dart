import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/markdown_codec.dart'
    show mondayOfSprintId, sprintId, two;
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/entities/sprint.dart';
import '../../domain/entities/kanban.dart';
import '../../domain/repositories.dart';

enum SprintStatus { loading, ready, failure }

/// Строки «сделано» из журнала: одна на задачу за день.
///
/// [explicit] — явные отметки о закрытых ⭐-задачах, они идут первыми и
/// журналом не дублируются.
List<String> buildDoneLines(
  List<DayLog> fact, {
  List<String> explicit = const [],
}) {
  final result = <String>[...explicit];
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

class SprintState extends Equatable {
  const SprintState({
    required this.status,
    this.sprint,
    this.fact = const [],
    this.history = const [],
    this.error = '',
    this.openSprintId,
    this.openSprintDone = const [],
  });

  final SprintStatus status;
  final Sprint? sprint;

  /// Факт по дням недели (пн–вс).
  final List<DayLog> fact;
  final List<SprintSummary> history;
  final String error;

  /// Раскрытая в истории неделя и её список сделанного (грузится по тапу).
  final String? openSprintId;
  final List<String> openSprintDone;

  /// Что сделано за неделю. Явные отметки о закрытых ⭐-задачах ПЛЮС всё,
  /// что реально попало в журнал.
  ///
  /// На одни ⭐ полагаться нельзя: список наполнялся только полностью
  /// закрытыми ⭐-задачами, а сами ⭐ снимаются при каждом переходе недели —
  /// чтобы сюда что-то попало, надо было заново отметить задачу звездой в
  /// понедельник и закрыть её целиком до воскресенья. На практике секция
  /// поэтому почти всегда пустовала.
  List<String> get doneLines =>
      buildDoneLines(fact, explicit: sprint?.doneWeek ?? const []);

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
    String? openSprintId,
    List<String>? openSprintDone,
    bool closeSprint = false,
  }) {
    return SprintState(
      status: status ?? this.status,
      sprint: sprint ?? this.sprint,
      fact: fact ?? this.fact,
      history: history ?? this.history,
      error: error ?? this.error,
      openSprintId: closeSprint ? null : (openSprintId ?? this.openSprintId),
      openSprintDone: closeSprint
          ? const []
          : (openSprintDone ?? this.openSprintDone),
    );
  }

  @override
  List<Object?> get props => [
    status,
    sprint,
    fact,
    history,
    error,
    openSprintId,
    openSprintDone,
  ];
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
            final prepared = _reconcileKanban(sprint, _weekTasks());
            emit(
              state.copyWith(
                status: SprintStatus.ready,
                sprint: prepared,
                fact: fact,
                history: history,
              ),
            );
            await _sprints.saveSprint(prepared, fact, weekTasks: _weekTasks());
          },
        );
      },
    );
  }

  /// Тап по неделе в истории: раскрыть её список сделанного либо свернуть.
  /// Данные берём из журнала — у SprintSummary своих записей нет.
  Future<void> toggleSprint(String id) async {
    if (state.openSprintId == id) {
      emit(state.copyWith(closeSprint: true));
      return;
    }
    final monday = mondayOfSprintId(id);
    if (monday == null) return;
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final result = await _journal.range(monday, sunday, _dailyGoal());
    emit(
      state.copyWith(
        openSprintId: id,
        openSprintDone: buildDoneLines(result.getOrElse((_) => const [])),
      ),
    );
  }

  Future<void> setGoal(int goal) async {
    final sprint = state.sprint;
    if (sprint == null || goal <= 0) return;
    await _save(sprint.copyWith(goal: goal));
  }

  Future<void> setMilestone(String milestone, {bool clearRef = false}) async {
    final sprint = state.sprint;
    if (sprint == null) return;
    await _save(
      sprint.copyWith(
        milestone: milestone.trim(),
        clearMilestoneId: clearRef,
      ),
    );
  }

  /// Установить ссылку на веху направления из лестницы.
  Future<void> setMilestoneRef(String milestoneId) async {
    final sprint = state.sprint;
    if (sprint == null) return;
    await _save(sprint.copyWith(milestoneId: milestoneId));
  }

  /// Снимок актуальных ⭐-задач дополняет доску, не меняя существующие статусы.
  Sprint _reconcileKanban(Sprint sprint, List<PomoTask> tasks) {
    final columns = sprint.kanbanColumns.length >= 2
        ? sprint.kanbanColumns
        : defaultKanbanColumns;
    final first = columns.first.id;
    final active = {for (final task in tasks) task.id: task};
    final validColumnIds = columns.map((column) => column.id).toSet();
    final cards = <KanbanCard>[];
    for (final card in sprint.kanbanCards) {
      final task = active[card.taskId];
      if (task == null) {
        // Активная карточка без задачи означает обычное удаление. Снимок
        // завершённой карточки, напротив, живёт до конца спринта.
        if (card.completed) cards.add(card);
      } else {
        cards.add(
          KanbanCard.fromTask(
            task,
            columnId: validColumnIds.contains(card.columnId)
                ? card.columnId
                : first,
            order: card.order,
            completed: card.completed,
          ),
        );
      }
    }
    final known = cards.map((card) => card.taskId).toSet();
    var nextOrder = cards.fold<int>(
          -1,
          (max, card) => card.order > max ? card.order : max,
        ) +
        1;
    for (final task in tasks) {
      final id = task.id;
      if (id == null || known.contains(id)) continue;
      cards.add(KanbanCard.fromTask(task, columnId: first, order: nextOrder++));
    }
    return sprint.copyWith(kanbanColumns: columns, kanbanCards: cards);
  }

  List<KanbanCard> cardsFor(List<PomoTask> tasks) {
    final sprint = state.sprint;
    if (sprint == null) return const [];
    return _reconcileKanban(sprint, tasks).kanbanCards;
  }

  Future<void> syncKanbanTask(PomoTask task, bool enabled) async {
    final sprint = state.sprint;
    final id = task.id;
    if (sprint == null || id == null) return;
    final cards = [...sprint.kanbanCards]..removeWhere((card) => card.taskId == id);
    if (enabled) {
      final maxOrder = cards.fold<int>(
        -1,
        (max, card) => card.order > max ? card.order : max,
      );
      cards.add(
        KanbanCard.fromTask(
          task,
          columnId: sprint.kanbanColumns.first.id,
          order: maxOrder + 1,
        ),
      );
    }
    await _save(sprint.copyWith(kanbanCards: cards));
  }

  Future<void> completeKanbanTask(PomoTask task) async {
    final sprint = state.sprint;
    final id = task.id;
    if (sprint == null || id == null) return;
    final last = sprint.kanbanColumns.last.id;
    final cards = [...sprint.kanbanCards];
    final index = cards.indexWhere((card) => card.taskId == id);
    final card = KanbanCard.fromTask(
      task,
      columnId: last,
      order: index >= 0 ? cards[index].order : cards.length,
      completed: true,
    );
    if (index >= 0) {
      cards[index] = card;
    } else {
      cards.add(card);
    }
    await _save(sprint.copyWith(kanbanCards: cards));
  }

  Future<void> moveKanbanCard(
    KanbanCard card, {
    required String columnId,
    String? beforeTaskId,
  }) async {
    final sprint = state.sprint;
    if (sprint == null) return;
    final cards = [...sprint.kanbanCards];
    final index = cards.indexWhere((item) => item.taskId == card.taskId);
    if (index < 0) return;
    final moving = card.copyWith(
      columnId: columnId,
      completed: columnId == sprint.kanbanColumns.last.id,
    );
    cards.removeAt(index);
    final insertAt = beforeTaskId == null
        ? cards.length
        : cards.indexWhere((item) => item.taskId == beforeTaskId);
    cards.insert(insertAt < 0 ? cards.length : insertAt, moving);
    final nextOrder = <String, int>{};
    for (var i = 0; i < cards.length; i++) {
      final item = cards[i];
      final order = nextOrder[item.columnId] ?? 0;
      nextOrder[item.columnId] = order + 1;
      cards[i] = item.copyWith(order: order);
    }
    await _save(sprint.copyWith(kanbanCards: cards));
  }

  Future<void> setKanbanColumns(List<KanbanColumn> columns) async {
    if (columns.length < 2) return;
    final sprint = state.sprint;
    if (sprint == null) return;
    final valid = columns.map((column) => column.id).toSet();
    final first = columns.first.id;
    final cards = [
      for (final card in sprint.kanbanCards)
        card.copyWith(columnId: valid.contains(card.columnId) ? card.columnId : first),
    ];
    await _save(sprint.copyWith(kanbanColumns: columns, kanbanCards: cards));
  }

  /// Очистить ссылку на веху направления (лестница пройдена или свободный текст).
  Future<void> clearMilestoneRef() async {
    final sprint = state.sprint;
    if (sprint == null) return;
    await _save(sprint.copyWith(clearMilestoneId: true));
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
