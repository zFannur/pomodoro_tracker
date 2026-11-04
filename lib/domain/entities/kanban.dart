import 'package:equatable/equatable.dart';

import 'pomo_task.dart';

/// Колонка доски текущего спринта. [id] не меняется при переименовании.
class KanbanColumn extends Equatable {
  const KanbanColumn({required this.id, required this.title});

  factory KanbanColumn.fromJson(Map<String, dynamic> json) => KanbanColumn(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  final String id;
  final String title;

  KanbanColumn copyWith({String? id, String? title}) => KanbanColumn(
        id: id ?? this.id,
        title: title ?? this.title,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  @override
  List<Object?> get props => [id, title];
}

/// Снимок задачи на доске. Для активной карточки свежие данные берутся из
/// [PomoTask], а снимок нужен для завершённых карточек, которые уже удалены
/// из активного списка.
class KanbanCard extends Equatable {
  const KanbanCard({
    required this.taskId,
    required this.description,
    required this.category,
    required this.durationMinutes,
    required this.columnId,
    required this.order,
    this.due,
    this.frog = false,
    this.milestoneId = '',
    this.completed = false,
  });

  factory KanbanCard.fromJson(Map<String, dynamic> json) => KanbanCard(
        taskId: json['taskId'] as String? ?? json['id'] as String? ?? '',
        description: json['desc'] as String? ?? '',
        category: json['cat'] as String? ?? '',
        durationMinutes: ((json['min'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
        columnId: json['columnId'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        due: json['due'] is String
            ? DateTime.tryParse(json['due'] as String)
            : null,
        frog: json['frog'] == true,
        milestoneId: json['ms'] as String? ?? '',
        completed: json['completed'] == true,
      );

  factory KanbanCard.fromTask(
    PomoTask task, {
    required String columnId,
    required int order,
    bool completed = false,
  }) => KanbanCard(
        taskId: task.id ?? '',
        description: task.description,
        category: task.category,
        durationMinutes: task.durationMinutes,
        columnId: columnId,
        order: order,
        due: task.due,
        frog: task.frog,
        milestoneId: task.milestoneId,
        completed: completed,
      );

  final String taskId;
  final String description;
  final String category;
  final int durationMinutes;
  final String columnId;
  final int order;
  final DateTime? due;
  final bool frog;
  final String milestoneId;
  final bool completed;

  KanbanCard copyWith({
    String? taskId,
    String? description,
    String? category,
    int? durationMinutes,
    String? columnId,
    int? order,
    DateTime? due,
    bool clearDue = false,
    bool? frog,
    String? milestoneId,
    bool? completed,
  }) => KanbanCard(
        taskId: taskId ?? this.taskId,
        description: description ?? this.description,
        category: category ?? this.category,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        columnId: columnId ?? this.columnId,
        order: order ?? this.order,
        due: clearDue ? null : (due ?? this.due),
        frog: frog ?? this.frog,
        milestoneId: milestoneId ?? this.milestoneId,
        completed: completed ?? this.completed,
      );

  PomoTask toTask() => PomoTask(
        id: taskId,
        description: description,
        category: category,
        durationMinutes: durationMinutes,
        due: due,
        frog: frog,
        week: true,
        milestoneId: milestoneId,
      );

  Map<String, dynamic> toJson() => {
        'id': taskId,
        'taskId': taskId,
        'desc': description,
        'cat': category,
        'min': durationMinutes,
        'columnId': columnId,
        'order': order,
        if (due != null) 'due': due!.toIso8601String(),
        if (frog) 'frog': true,
        if (milestoneId.isNotEmpty) 'ms': milestoneId,
        if (completed) 'completed': true,
      };

  @override
  List<Object?> get props => [
        taskId,
        description,
        category,
        durationMinutes,
        columnId,
        order,
        due,
        frog,
        milestoneId,
        completed,
      ];
}

const defaultKanbanColumns = [
  KanbanColumn(id: 'waiting', title: 'ОЖИДАЕТ'),
  KanbanColumn(id: 'working', title: 'В РАБОТЕ'),
  KanbanColumn(id: 'testing', title: 'ТЕСТ'),
  KanbanColumn(id: 'done', title: 'ГОТОВО'),
];
