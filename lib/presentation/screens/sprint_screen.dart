import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart';
import '../../domain/entities/direction.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/entities/sprint.dart';
import '../cubits/directions_cubit.dart';
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

class _SprintBody extends StatefulWidget {
  const _SprintBody({required this.state});

  final SprintState state;

  @override
  State<_SprintBody> createState() => _SprintBodyState();
}

class _SprintBodyState extends State<_SprintBody> {
  /// Раскрытый день недели. Держим дату: факт пересобирается при обновлении.
  DateTime? _openDay;

  /// Имя направления, у которого только что закрыли последнюю ступень лестницы.
  String? _ladderCompletedDirName;

  void _toggleDay(DayLog day) => setState(
    () => _openDay = _openDay == day.date ? null : day.date,
  );

  Widget? _openDayCard() {
    final date = _openDay;
    if (date == null) return null;
    for (final d in widget.state.fact) {
      if (d.date != date) continue;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SectionCard(
          title: S.dayDoneTitle(dateHuman(d.date)),
          child: DayDoneList(day: d),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
                '${S.sprintWord} ${sprint.id} · ${dateHuman(sprint.start)} – ${dateHuman(sprint.end)}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              // Веха недели — тянется из лестницы направления либо свободный текст.
              _buildMilestoneSection(context, sprint),
              const SizedBox(height: 12),
              SectionCard(
                title: S.weekTasksTitle,
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.star, size: 16),
                  label: Text(S.pickWeekTasks),
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
              // Секция показывается всегда: скрытая при пустом списке, она
              // выглядела как «не работает», а не как «за неделю пока пусто».
              SectionCard(
                title: S.doneWeekTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.doneLines.isEmpty)
                      Text(
                        S.doneWeekEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    for (final line in state.doneLines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(line, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  StatTile(
                    label: S.sprintFact,
                    value: '${state.factPomodoros} / ${sprint.goal} 🍅',
                  ),
                  const SizedBox(width: 8),
                  StatTile(
                    label: S.statTime,
                    value: formatMinutesUi(state.factMinutes),
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
                child: DaysBarChart(
                  days: state.fact,
                  goal: settings.dailyGoal,
                  onDayTap: _toggleDay,
                ),
              ),
              // Раскрытый день — списком под графиком, повторный тап сворачивает.
              ?_openDayCard(),
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
                          Text(S.colWeek, style: theme.textTheme.labelMedium),
                          Text(S.colGoal, style: theme.textTheme.labelMedium),
                          Text(S.sprintFact, style: theme.textTheme.labelMedium),
                          Text(S.statTime, style: theme.textTheme.labelMedium),
                        ],
                      ),
                      for (final s in state.history)
                        TableRow(
                          decoration: s.id == state.openSprintId
                              ? BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                )
                              : null,
                          children: [
                            for (final cell in [
                              Text(s.id),
                              Text('${s.goal} 🍅'),
                              Text('${s.fact} 🍅'),
                              Text(formatMinutesUi(s.minutes)),
                            ])
                              // Тап по всей строке: TableRowInkWell ловит
                              // нажатие на любой ячейке.
                              TableRowInkWell(
                                onTap: () => context
                                    .read<SprintCubit>()
                                    .toggleSprint(s.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: cell,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              // Раскрытая неделя — списком снизу, чтобы не ломать таблицу.
              if (state.openSprintId != null) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: '${S.doneWeekTitle} · ${state.openSprintId}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.openSprintDone.isEmpty)
                        Text(
                          S.doneWeekEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      for (final line in state.openSprintDone)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(line, style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Секция вехи недели: берется из лестницы направления (Sprint.milestoneId)
  /// либо свободный текст (Sprint.milestone) для совместимости со старыми неделями.
  Widget _buildMilestoneSection(BuildContext context, Sprint sprint) {
    final theme = Theme.of(context);
    DirectionsState? directionsState;
    try {
      directionsState = context.watch<DirectionsCubit>().state;
    } catch (_) {
      directionsState = null;
    }

    Milestone? milestone;
    Direction? direction;
    var ladderIndex = 0;
    var ladderTotal = 0;

    if (directionsState != null && sprint.milestoneId.isNotEmpty) {
      milestone = directionsState.milestoneById(sprint.milestoneId);
      if (milestone != null) {
        direction = directionsState.directionOf(milestone);
        if (direction != null) {
          final lad = ladder(directionsState.milestones, direction.id);
          ladderIndex = lad.indexOf(milestone) + 1;
          ladderTotal = lad.length;
        }
      }
    }

    Widget content;
    if (milestone != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (direction != null)
            Text(
              '${direction.name} · ${S.ladderProgress(ladderIndex, ladderTotal)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            milestone.title,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: Text(S.courseCloseMilestone),
            onPressed: () => _closeMilestone(
              context,
              sprint,
              milestone!,
              direction,
              directionsState!,
            ),
          ),
        ],
      );
    } else if (_ladderCompletedDirName != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '$_ladderCompletedDirName: ${S.courseLadderPassed}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          ..._buildTakeNextButton(context, directionsState),
        ],
      );
    } else if (sprint.milestone.isNotEmpty) {
      content = Text(
        sprint.milestone,
        style: theme.textTheme.titleMedium,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.milestoneHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          ..._buildTakeNextButton(context, directionsState),
        ],
      );
    }

    return SectionCard(
      title: S.milestone,
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: S.pickMilestone,
        onPressed: () => _showPickMilestoneDialog(
          context,
          sprint,
          directionsState,
        ),
      ),
      child: content,
    );
  }

  List<Widget> _buildTakeNextButton(
    BuildContext context,
    DirectionsState? directionsState,
  ) {
    if (directionsState == null) return const [];
    Milestone? nextFirstOpen;
    Direction? nextFirstDir;
    for (final d in directionsState.active) {
      final next = nextOpen(directionsState.milestones, d.id);
      if (next != null) {
        nextFirstOpen = next;
        nextFirstDir = d;
        break;
      }
    }
    if (nextFirstOpen == null || nextFirstDir == null) return const [];
    return [
      const SizedBox(height: 10),
      FilledButton.tonalIcon(
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text(
          '${S.takeNextMilestone}: ${nextFirstDir.name} → ${nextFirstOpen.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: () {
          setState(() {
            _ladderCompletedDirName = null;
          });
          context.read<SprintCubit>().setMilestoneRef(nextFirstOpen!.id);
        },
      ),
    ];
  }

  Future<void> _closeMilestone(
    BuildContext context,
    Sprint sprint,
    Milestone milestone,
    Direction? direction,
    DirectionsState directionsState,
  ) async {
    final now = DateTime.now();
    await context.read<DirectionsCubit>().closeMilestone(
      milestone.id,
      sprint.id,
      now,
    );
    final dirId = milestone.directionId;
    final updated = [
      for (final m in directionsState.milestones)
        if (m.id == milestone.id)
          m.copyWith(doneSprint: sprint.id, doneAt: now)
        else
          m,
    ];
    final next = nextOpen(updated, dirId);
    if (next != null) {
      if (context.mounted) {
        await context.read<SprintCubit>().setMilestoneRef(next.id);
      }
    } else {
      if (context.mounted) {
        await context.read<SprintCubit>().clearMilestoneRef();
        setState(() {
          _ladderCompletedDirName = direction?.name;
        });
      }
    }
  }

  void _showPickMilestoneDialog(
    BuildContext context,
    Sprint sprint,
    DirectionsState? directionsState,
  ) {
    final theme = Theme.of(context);
    final active = directionsState?.active ?? const [];
    final hasActiveSteps = active.any(
      (d) => ladder(directionsState!.milestones, d.id).any((m) => !m.done),
    );

    if (directionsState == null || !hasActiveSteps) {
      _editMilestone(context, sprint.milestone);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.pickMilestone),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final dir in active) ...[
                  if (ladder(directionsState.milestones, dir.id)
                      .where((m) => !m.done)
                      .toList()
                      case final openSteps when openSteps.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        dir.name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (final m in openSteps)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined, size: 20),
                        title: Text(m.title, style: theme.textTheme.bodyMedium),
                        onTap: () {
                          setState(() {
                            _ladderCompletedDirName = null;
                          });
                          context.read<SprintCubit>().setMilestoneRef(m.id);
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                  ],
                ],
                const Divider(height: 20),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note, size: 22),
                  title: Text(S.customMilestone, style: theme.textTheme.bodyMedium),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _editMilestone(context, sprint.milestone);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.close),
          ),
        ],
      ),
    );
  }

  void _editMilestone(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.milestone),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                helperText: S.milestoneHint,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(S.close),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(S.save),
              ),
            ],
          ),
        )
        .then((value) {
          if (value != null && context.mounted) {
            setState(() {
              _ladderCompletedDirName = null;
            });
            context.read<SprintCubit>().setMilestone(value, clearRef: true);
          }
        })
        .whenComplete(controller.dispose);
  }

  static void _editGoal(BuildContext context, int current) {
    final controller = TextEditingController(text: '$current');
    showDialog<int>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.sprintGoal),
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
                child: Text(S.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(int.tryParse(controller.text)),
                child: Text(S.save),
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
            '${task.pomos(pomodoro)} 🍅 · ${formatMinutesUi(task.durationMinutes)}',
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
