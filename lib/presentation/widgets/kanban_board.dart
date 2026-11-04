import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/kanban.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/entities/sprint.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/sprint_cubit.dart';
import '../cubits/tasks_cubit.dart';
import 'common.dart';
import '../screens/planner_dialog.dart';

/// Доска текущего спринта. Колонки синхронизируются в Sprint, а переключатель
/// режима живёт в локальных AppSettings.
class KanbanBoard extends StatelessWidget {
  const KanbanBoard({super.key});

  @override
  Widget build(BuildContext context) {
    final sprintState = context.watch<SprintCubit>().state;
    final tasks = context.watch<TasksCubit>().weekTasks();
    final theme = Theme.of(context);
    final sprint = sprintState.sprint;
    if (sprintState.status == SprintStatus.failure) {
      return ErrorPane(
        message: sprintState.error,
        onRetry: () => context.read<SprintCubit>().refresh(),
      );
    }
    if (sprintState.status == SprintStatus.loading || sprint == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cards = context.read<SprintCubit>().cardsFor(tasks);
    final allCards = [...cards]..sort((a, b) => a.order.compareTo(b.order));
    final total = allCards.length;
    final activeById = <String, PomoTask>{
      for (final task in tasks)
        if (task.id != null) task.id!: task,
    };
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final daysLeft = sprint.end.isBefore(startOfToday)
        ? 0
        : sprint.end.difference(startOfToday).inDays + 1;
    final passedDays = (7 - daysLeft).clamp(1, 7);
    final doneCount = allCards.where((card) => card.completed).length;
    final neededPerDay = daysLeft == 0 ? 0.0 : (total - doneCount) / daysLeft;
    final actualPerDay = doneCount / passedDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KanbanSummary(
          daysLeft: daysLeft,
          remaining: total - doneCount,
          neededPerDay: neededPerDay,
          actualPerDay: actualPerDay,
        ),
        const SizedBox(height: 12),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(
                  Icons.view_kanban_outlined,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 8),
                Text(S.kanbanNoTasks, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(S.kanbanAddSprintTask, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => showPlannerDialog(context),
                  icon: const Icon(Icons.inbox_outlined),
                  label: Text(S.planner),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final column in sprint.kanbanColumns)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _KanbanColumn(
                        sprint: sprint,
                        column: column,
                        totalCards: total,
                        cards: [
                          for (final card in cards)
                            if (card.columnId == column.id) card,
                        ]..sort((a, b) => a.order.compareTo(b.order)),
                        activeById: activeById,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _KanbanSummary extends StatelessWidget {
  const _KanbanSummary({
    required this.daysLeft,
    required this.remaining,
    required this.neededPerDay,
    required this.actualPerDay,
  });

  final int daysLeft;
  final int remaining;
  final double neededPerDay;
  final double actualPerDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          S.kanbanDaysLeft(daysLeft, remaining),
          style: theme.textTheme.labelLarge,
        ),
        Text(
          S.kanbanPace(
            neededPerDay.toStringAsFixed(1),
            actualPerDay.toStringAsFixed(1),
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.sprint,
    required this.column,
    required this.totalCards,
    required this.cards,
    required this.activeById,
  });

  final Sprint sprint;
  final KanbanColumn column;
  final int totalCards;
  final List<KanbanCard> cards;
  final Map<String, PomoTask> activeById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = totalCards == 0
        ? 0
        : (cards.length * 100 / totalCards).round();
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                column.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                S.kanbanColumnPercent(cards.length, totalCards, percent),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (cards.isEmpty) ...[
                Expanded(
                  child: _KanbanDropSlot(
                    columnId: column.id,
                    fill: true,
                    onMove: (moving, before) =>
                        _move(context, moving, column.id, before),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    S.emptyBucket,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ] else ...[
                for (final card in cards) ...[
                  _KanbanDropSlot(
                    columnId: column.id,
                    beforeTaskId: card.taskId,
                    onMove: (moving, before) =>
                        _move(context, moving, column.id, before),
                  ),
                  _KanbanCardItem(
                    card: card,
                    activeTask: activeById[card.taskId],
                  ),
                ],
                Expanded(
                  child: _KanbanDropSlot(
                    columnId: column.id,
                    fill: true,
                    onMove: (moving, before) =>
                        _move(context, moving, column.id, before),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Icon(Icons.add, size: 16, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  void _move(
    BuildContext context,
    KanbanCard card,
    String columnId,
    String? beforeTaskId,
  ) {
    unawaited(_moveAsync(context, card, columnId, beforeTaskId));
  }

  Future<void> _moveAsync(
    BuildContext context,
    KanbanCard card,
    String columnId,
    String? beforeTaskId,
  ) async {
    final tasks = context.read<TasksCubit>();
    final sprintCubit = context.read<SprintCubit>();
    final lastId = sprint.kanbanColumns.last.id;
    if (columnId == lastId && !card.completed) {
      await tasks.closeForKanban(card.taskId);
    } else if (columnId != lastId && card.completed) {
      await tasks.restoreKanbanCard(card);
    }
    await sprintCubit.moveKanbanCard(
      card,
      columnId: columnId,
      beforeTaskId: beforeTaskId,
    );
  }
}

class _KanbanDropSlot extends StatelessWidget {
  const _KanbanDropSlot({
    required this.columnId,
    required this.onMove,
    this.beforeTaskId,
    this.fill = false,
  });

  final String columnId;
  final String? beforeTaskId;
  final bool fill;
  final void Function(KanbanCard card, String? beforeTaskId) onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<KanbanCard>(
      key: ValueKey('kanban-drop-$columnId-${beforeTaskId ?? 'end'}'),
      onWillAcceptWithDetails: (details) => details.data.taskId != beforeTaskId,
      onAcceptWithDetails: (details) => onMove(details.data, beforeTaskId),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        final color = theme.colorScheme.primary;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: fill ? null : (active ? 34 : 12),
          constraints: fill ? const BoxConstraints(minHeight: 80) : null,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(6),
            border: active ? Border.all(color: color, width: 1.5) : null,
          ),
          child: active
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.vertical_align_center, size: 16, color: color),
                    const SizedBox(width: 5),
                    Text(
                      S.kanbanDropHere,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Container(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
        );
      },
    );
  }
}

class _KanbanCardItem extends StatelessWidget {
  const _KanbanCardItem({required this.card, required this.activeTask});

  final KanbanCard card;
  final PomoTask? activeTask;

  @override
  Widget build(BuildContext context) {
    final pomodoro = context
        .read<SettingsCubit>()
        .state
        .settings
        .scheme
        .pomodoro;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Draggable<KanbanCard>(
        data: card,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 240,
            child: _KanbanCard(
              card: card,
              activeTask: activeTask,
              pomodoro: pomodoro,
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _KanbanCard(
            card: card,
            activeTask: activeTask,
            pomodoro: pomodoro,
          ),
        ),
        child: _KanbanCard(
          card: card,
          activeTask: activeTask,
          pomodoro: pomodoro,
        ),
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.card,
    required this.activeTask,
    required this.pomodoro,
  });

  final KanbanCard card;
  final PomoTask? activeTask;
  final int pomodoro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = activeTask;
    final minutes = task?.durationMinutes ?? card.durationMinutes;
    final category = task?.category ?? card.category;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: card.completed
              ? theme.colorScheme.primary.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${card.frog ? '🐸 ' : ''}${task?.description ?? card.description}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CategoryChip(category),
              Text(
                '$minutes ${S.minShort} · ${task?.pomos(pomodoro) ?? ((minutes / pomodoro).ceil())} 🍅',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
