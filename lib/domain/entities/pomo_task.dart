import 'package:equatable/equatable.dart';

/// Вкладка планировщика — вычисляется из даты `due`, как в оригинале.
enum PlannerTab { inbox, tomorrow, week, later }

/// Задача плана (TODO) или планировщика. Оценка хранится в минутах и
/// уменьшается по мере выполнения помидоров; флага «выполнено» нет —
/// задача исчезает из плана, когда минуты выработаны.
class PomoTask extends Equatable {
  const PomoTask({
    required this.description,
    required this.category,
    required this.durationMinutes,
    this.due,
    this.frog = false,
    this.week = false,
    this.id,
  });

  /// Стабильный id для JSON-хранилища и будущего синка. null — задача из
  /// markdown или свежесозданная; id выдаёт репозиторий при сохранении.
  final String? id;

  final String description;
  final String category;

  /// Оставшаяся оценка в минутах (>= 1).
  final int durationMinutes;

  /// Срок (для задач планировщика); null — «Входящие».
  final DateTime? due;

  /// 🐸 Лягушка дня — самая противная задача, делается первой.
  final bool frog;

  /// ⭐ Задача недели (двигает веху спринта).
  final bool week;

  /// Сколько помидоров показывать на строке при длине помидора [pomodoroMinutes].
  int pomos(int pomodoroMinutes) => pomodoroMinutes <= 0
      ? 1
      : (durationMinutes / pomodoroMinutes).ceil().clamp(1, 999);

  /// Вкладка планировщика по сроку: просроченные и без даты — «Входящие».
  PlannerTab tab(DateTime now) {
    final d = due;
    if (d == null) return PlannerTab.inbox;
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    if (d.isBefore(endOfToday)) return PlannerTab.inbox;
    final endOfTomorrow = DateTime(now.year, now.month, now.day + 2);
    if (d.isBefore(endOfTomorrow)) return PlannerTab.tomorrow;
    final endOfWeek = DateTime(
      now.year,
      now.month,
      now.day + (8 - now.weekday),
    );
    if (d.isBefore(endOfWeek)) return PlannerTab.week;
    return PlannerTab.later;
  }

  PomoTask copyWith({
    String? description,
    String? category,
    int? durationMinutes,
    DateTime? due,
    bool clearDue = false,
    bool? frog,
    bool? week,
    String? id,
  }) {
    return PomoTask(
      description: description ?? this.description,
      category: category ?? this.category,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      due: clearDue ? null : (due ?? this.due),
      frog: frog ?? this.frog,
      week: week ?? this.week,
      id: id ?? this.id,
    );
  }

  @override
  List<Object?> get props => [
    id,
    description,
    category,
    durationMinutes,
    due,
    frog,
    week,
  ];
}

/// Содержимое файла задач: TODO («Сегодня») + планировщик.
class TasksFile extends Equatable {
  const TasksFile({required this.todo, required this.planner});

  final List<PomoTask> todo;
  final List<PomoTask> planner;

  TasksFile copyWith({List<PomoTask>? todo, List<PomoTask>? planner}) =>
      TasksFile(todo: todo ?? this.todo, planner: planner ?? this.planner);

  @override
  List<Object?> get props => [todo, planner];
}

/// Пункт чек-листа спринта (наша адаптация, не из оригинала).
class SprintTask extends Equatable {
  const SprintTask({
    required this.description,
    required this.category,
    this.done = false,
  });

  final String description;
  final String category;
  final bool done;

  SprintTask copyWith({String? description, String? category, bool? done}) {
    return SprintTask(
      description: description ?? this.description,
      category: category ?? this.category,
      done: done ?? this.done,
    );
  }

  @override
  List<Object?> get props => [description, category, done];
}
