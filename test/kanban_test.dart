import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';
import 'package:pomodoro_tracker/domain/entities/kanban.dart';

void main() {
  test('канбан-карточка и колонка сохраняют формат JSON', () {
    const column = KanbanColumn(id: 'work', title: 'В РАБОТЕ');
    final card = KanbanCard(
      taskId: 'task-1',
      description: 'Проверить сборку',
      category: 'работа',
      durationMinutes: 50,
      columnId: column.id,
      order: 2,
      completed: true,
    );

    expect(KanbanColumn.fromJson(column.toJson()), column);
    expect(KanbanCard.fromJson(card.toJson()), card);
  });

  test('канбан-данные объединяются при синхронизации', () {
    Map<String, dynamic> sprint(Map<String, dynamic> kanban) => {
      'goal': 40,
      'kanban': kanban,
    };
    final local = jsonEncode({
      'schema': 2,
      'todo': [],
      'planner': [],
      'days': {},
      'sprints': {
        '2026-W30': sprint({
          'columns': [
            {'id': 'waiting', 'title': 'ОЖИДАЕТ'},
          ],
          'cards': [
            {'id': 'a', 'taskId': 'a', 'columnId': 'waiting', 'order': 0},
          ],
        }),
      },
      'graves': {},
    });
    final remote = jsonEncode({
      'schema': 2,
      'todo': [],
      'planner': [],
      'days': {},
      'sprints': {
        '2026-W30': sprint({
          'columns': [
            {'id': 'waiting', 'title': 'ОЖИДАЕТ'},
            {'id': 'done', 'title': 'ГОТОВО'},
          ],
          'cards': [
            {'id': 'b', 'taskId': 'b', 'columnId': 'done', 'order': 0},
          ],
        }),
      },
      'graves': {},
    });

    final result = jsonDecode(
      mergeData(local, remote, localWins: true),
    ) as Map<String, dynamic>;
    final kanban = (result['sprints'] as Map)['2026-W30']['kanban'];
    expect((kanban['columns'] as List).length, 2);
    expect((kanban['cards'] as List).map((item) => item['id']), ['a', 'b']);
  });
}
