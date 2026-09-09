import 'package:equatable/equatable.dart';

/// Недельный спринт (пн–вс): веха + задачи недели (⭐ в общем списке задач).
class Sprint extends Equatable {
  const Sprint({
    required this.id,
    required this.start,
    required this.goal,
    this.milestone = '',
    this.milestoneId = '',
    this.doneWeek = const [],
  });

  /// Идентификатор вида `2026-W29`.
  final String id;

  /// Понедельник недели спринта (только дата).
  final DateTime start;

  /// Цель в помидорах на неделю.
  final int goal;

  /// Веха недели — тонкий срез до реальности, проверяется бинарно.
  final String milestone;

  /// Ссылка на ступень лестницы вех направления. Пусто — вне направлений.
  final String milestoneId;

  /// Закрытые за неделю ⭐-задачи (строки для секции «Сделано за неделю»).
  final List<String> doneWeek;

  DateTime get end => DateTime(start.year, start.month, start.day + 6);

  Sprint copyWith({
    int? goal,
    String? milestone,
    String? milestoneId,
    bool clearMilestoneId = false,
    List<String>? doneWeek,
  }) {
    return Sprint(
      id: id,
      start: start,
      goal: goal ?? this.goal,
      milestone: milestone ?? this.milestone,
      milestoneId: clearMilestoneId ? '' : (milestoneId ?? this.milestoneId),
      doneWeek: doneWeek ?? this.doneWeek,
    );
  }

  @override
  List<Object?> get props => [id, start, goal, milestone, milestoneId, doneWeek];
}

/// Сводка прошедшего спринта для истории.
class SprintSummary extends Equatable {
  const SprintSummary({
    required this.id,
    required this.goal,
    required this.fact,
    required this.minutes,
  });

  final String id;
  final int goal;
  final int fact;
  final int minutes;

  @override
  List<Object?> get props => [id, goal, fact, minutes];
}
