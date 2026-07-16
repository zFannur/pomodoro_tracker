import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/sprint_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../widgets/common.dart';
import 'planner_dialog.dart';

/// «Неделя»: веха недели + ⭐-задачи из общего списка + факт по дням.
class SprintScreen extends StatelessWidget {
  const SprintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SprintCubit, SprintState>(
      builder: (context, state) {
        return switch (state.status) {
          SprintStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          SprintStatus.failure => ErrorPane(
            message: state.error,
            onRetry: () => context.read<SprintCubit>().refresh(),
          ),
          SprintStatus.ready => _SprintBody(state: state),
        };
      },
    );
  }
}

class _SprintBody extends StatelessWidget {
  const _SprintBody({required this.state});

  final SprintState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sprint = state.sprint;
    if (sprint == null) {
      return Center(child: Text(S.loading, style: theme.textTheme.bodyMedium));
    }
    final tasksState = context.watch<TasksCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;
    final pomodoro = settings.scheme.pomodoro;
    final weekTodo = <(PomoTask, bool)>[
      for (final t in tasksState.todo)
        if (t.week) (t, false),
      for (final t in tasksState.planner)
        if (t.week) (t, true),
    ];
    final percent = sprint.goal > 0
        ? (state.factPomodoros / sprint.goal).clamp(0.0, 1.0)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Спринт ${sprint.id} · ${dateHuman(sprint.start)} – ${dateHuman(sprint.end)}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              // Веха недели — стержень: задачи недели двигают её.
              SectionCard(
                title: S.milestone,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: S.milestone,
                  onPressed: () => _editMilestone(context, sprint.milestone),
                ),
                child: Text(
                  sprint.milestone.isEmpty ? S.milestoneHint : sprint.milestone,
                  style: sprint.milestone.isEmpty
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: S.weekTasksTitle,
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.star, size: 16),
                  label: const Text(S.pickWeekTasks),
                  onPressed: () => showPlannerDialog(context),
                ),
                child: weekTodo.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          S.weekTasksEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (final (task, inPlanner) in weekTodo)
                            _WeekTaskRow(
                              task: task,
                              inPlanner: inPlanner,
                              pomodoro: pomodoro,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              if (sprint.doneWeek.isNotEmpty) ...[
                SectionCard(
                  title: S.doneWeekTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in sprint.doneWeek)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(line, style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  StatTile(
                    label: S.sprintFact,
                    value: '${state.factPomodoros} / ${sprint.goal} 🍅',
                  ),
                  const SizedBox(width: 8),
                  StatTile(
                    label: S.statTime,
                    value: formatMinutes(state.factMinutes),
                  ),
                  const SizedBox(width: 8),
                  StatTile(
                    label: S.sprintVelocity,
                    value: '${state.velocity.toStringAsFixed(1)} ${S.perDay}',
                  ),
                  const SizedBox(width: 8),
                  StatTile(label: S.forecast, value: '${state.forecast} 🍅'),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title:
                    '${S.sprintGoal}: ${sprint.goal} · ${(percent * 100).round()}%',
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: S.sprintGoal,
                  onPressed: () => _editGoal(context, sprint.goal),
                ),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: S.sprintByDay,
                child: DaysBarChart(days: state.fact, goal: settings.dailyGoal),
              ),
              const SizedBox(height: 12),
              if (state.history.isNotEmpty)
                SectionCard(
                  title: S.sprintHistory,
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(),
                      2: FlexColumnWidth(),
                      3: FlexColumnWidth(),
                    },
                    children: [
                      TableRow(
                        children: [
                          Text('Неделя', style: theme.textTheme.labelMedium),
                          Text('Цель', style: theme.textTheme.labelMedium),
                          Text('Факт', style: theme.textTheme.labelMedium),
                          Text('Время', style: theme.textTheme.labelMedium),
                        ],
                      ),
                      for (final s in state.history)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(s.id),
                            ),
                            Text('${s.goal} 🍅'),
                            Text('${s.fact} 🍅'),
                            Text(formatMinutes(s.minutes)),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _editMilestone(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(S.milestone),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                helperText: S.milestoneHint,
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(S.close),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text(S.save),
              ),
            ],
          ),
        )
        .then((value) {
          if (value != null && context.mounted) {
            context.read<SprintCubit>().setMilestone(value);
          }
        })
        .whenComplete(controller.dispose);
  }

  static void _editGoal(BuildContext context, int current) {
    final controller = TextEditingController(text: '$current');
    showDialog<int>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(S.sprintGoal),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (v) =>
                  Navigator.of(dialogContext).pop(int.tryParse(v)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(S.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(int.tryParse(controller.text)),
                child: const Text(S.save),
              ),
            ],
          ),
        )
        .then((value) {
          if (value != null && context.mounted) {
            context.read<SprintCubit>().setGoal(value);
          }
        })
        .whenComplete(controller.dispose);
  }
}

class _WeekTaskRow extends StatelessWidget {
  const _WeekTaskRow({
    required this.task,
    required this.inPlanner,
    required this.pomodoro,
  });

  final PomoTask task;
  final bool inPlanner;
  final int pomodoro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TasksCubit>();
    // Индекс — в момент клика: список мог сдвинуться после build.
    void act(void Function(int index) fn) {
      final i = inPlanner
          ? cubit.plannerIndexOf(task)
          : cubit.todoIndexOf(task);
      if (i >= 0) fn(i);
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CategoryChip(task.category),
      title: Text(
        '${task.frog ? '🐸 ' : ''}${task.description}',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        inPlanner ? S.planner : S.periodToday,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${task.pomos(pomodoro)} 🍅 · ${formatMinutes(task.durationMinutes)}',
            style: theme.textTheme.labelMedium,
          ),
          if (inPlanner)
            IconButton(
              tooltip: S.toToday,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.today, size: 16),
              onPressed: () => act(cubit.plannerToToday),
            )
          else
            IconButton(
              tooltip: '↩ ${S.menuToInbox}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.move_to_inbox_outlined, size: 16),
              onPressed: () => act((i) => cubit.postpone(i, PlannerTab.inbox)),
            ),
        ],
      ),
    );
  }
}
