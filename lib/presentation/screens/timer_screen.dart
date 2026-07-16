import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/markdown_codec.dart' show formatMinutes;
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/journal_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../cubits/timer_cubit.dart';
import '../widgets/common.dart';
import 'planner_dialog.dart';

/// Главная страница: таймер + «Запланировано» + «Сделано» — один поток,
/// как на оригинале.
class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: const Column(
            children: [
              _TimerBlock(),
              SizedBox(height: 24),
              _TodoSection(),
              SizedBox(height: 24),
              _DoneSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Таймер
// ---------------------------------------------------------------------------

class _TimerBlock extends StatelessWidget {
  const _TimerBlock();

  static String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Стоп бегущего помидора: спросить «на чём встал» (можно пропустить).
  static Future<void> _stopWithNote(BuildContext context) async {
    final timer = context.read<TimerCubit>();
    final journal = context.read<JournalCubit>();
    final wasWorking =
        timer.state.mode == TimerMode.pomodoro &&
        (timer.state.running || timer.state.paused) &&
        timer.state.remaining < timer.state.total;
    timer.stop();
    if (!wasWorking) return;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(S.whereStopped),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: S.whereStoppedHint,
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(S.withoutNote),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text(S.save),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (note != null && note.trim().isNotEmpty) {
      await journal.addNote(note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timer = context.watch<TimerCubit>().state;
    final tasks = context.watch<TasksCubit>().state;
    final journal = context.watch<JournalCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;

    final doneCount = journal.sessions.length;
    final header = switch (timer.mode) {
      TimerMode.pomodoro => '${S.pomodoroWord}${doneCount + 1}',
      TimerMode.shortBreak => S.shortBreakTitle,
      TimerMode.longBreak => S.longBreakTitle,
    };
    final showDelay =
        timer.stopped &&
        doneCount > 0 &&
        tasks.todo.isNotEmpty &&
        timer.delaysMs >= 60000;

    // Акцент по режиму: работа — томатный, перерыв — зелёный.
    final accent = timer.isBreak
        ? AppTheme.rest(theme.colorScheme)
        : theme.colorScheme.primary;
    final progress = timer.inOvertime
        ? 1.0
        : timer.total > 0
        ? (1 - timer.remaining / timer.total).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Настройки живут внизу NavigationRail; здесь — только полный экран.
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: S.fullscreen,
                icon: const Icon(Icons.fullscreen),
                onPressed: () async {
                  final isFull = await windowManager.isFullScreen();
                  await windowManager.setFullScreen(!isFull);
                },
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                header,
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (timer.mode == TimerMode.pomodoro) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: S.series,
                  child: Text(
                    '(${timer.series + 1})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (timer.interruptions > 0)
                  Tooltip(
                    message: '${S.interruptionsLabel} · ${timer.interruptions}',
                    child: Text(
                      ' ${'′' * timer.interruptions}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
              if (timer.isBreak)
                TextButton(
                  onPressed: () => context.read<TimerCubit>().skipBreak(),
                  child: Text('${S.skip}${timer.confirmArmed ? '?' : ''}'),
                ),
              if (timer.stopped)
                IconButton(
                  tooltip: S.forwardHint,
                  iconSize: 18,
                  icon: const Icon(Icons.fast_forward),
                  onPressed: () => context.read<TimerCubit>().forward(),
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Симметрия: слева зеркало кнопки «+1 мин» справа.
              const SizedBox(width: 48),
              Text(
                timer.inOvertime
                    ? '+ ${_format(timer.overtime)}'
                    : _format(timer.remaining),
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: 92,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 2,
                  color: timer.inOvertime
                      ? accent
                      : theme.colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                tooltip: S.prolong,
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => context.read<TimerCubit>().prolong(
                  HardwareKeyboard.instance.isShiftPressed ? 5 : 1,
                ),
              ),
            ],
          ),
          if (timer.inOvertime)
            Text(
              S.overtime,
              style: theme.textTheme.labelMedium?.copyWith(color: accent),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: 320,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 14),
          _NowCard(task: tasks.current),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buttons(context, timer, settings, showDelay),
          ),
          const SizedBox(height: 8),
          Text(
            timer.stopped && timer.delaysMs >= 10 * 60000
                ? S.stuckHint
                : S.hintKeys,
            style: theme.textTheme.labelSmall?.copyWith(
              color: timer.stopped && timer.delaysMs >= 10 * 60000
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buttons(
    BuildContext context,
    TimerState timer,
    AppSettings settings,
    bool showDelay,
  ) {
    final cubit = context.read<TimerCubit>();
    final scheme = Theme.of(context).colorScheme;
    // Взведённое подтверждение (Esc Esc) — кнопка предупреждающе краснеет.
    final armedStyle = OutlinedButton.styleFrom(
      foregroundColor: scheme.error,
      side: BorderSide(color: scheme.error),
    );
    final stopLabel =
        '${S.stop}${timer.confirmArmed && !timer.isBreak ? '?' : ''}';
    if (timer.inOvertime) {
      return [
        FilledButton.icon(
          onPressed: () => cubit.doneEarly(),
          icon: const Icon(Icons.check),
          label: const Text(S.doneEarly),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _stopWithNote(context),
          icon: const Icon(Icons.stop),
          label: const Text(S.stop),
        ),
      ];
    }
    return switch (timer.run) {
      TimerRun.stopped => [
        FilledButton.icon(
          onPressed: cubit.start,
          icon: const Icon(Icons.play_arrow),
          label: const Text(S.start),
        ),
        const SizedBox(width: 12),
        // Простой — информационный чип, а не «сломанная» серая кнопка.
        if (showDelay)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.tertiary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${S.delayLabel}: ${formatMinutes(timer.delaysMs ~/ 60000)}',
              style: TextStyle(color: scheme.tertiary),
            ),
          )
        else
          const OutlinedButton(onPressed: null, child: Text(S.stop)),
      ],
      TimerRun.running => [
        FilledButton.tonalIcon(
          onPressed: cubit.pause,
          icon: const Icon(Icons.pause),
          label: const Text(S.pause),
        ),
        const SizedBox(width: 12),
        if (timer.isBreak)
          OutlinedButton(
            onPressed: cubit.skipBreak,
            style: timer.confirmArmed ? armedStyle : null,
            child: Text('${S.skip}${timer.confirmArmed ? '?' : ''}'),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _stopWithNote(context),
            style: timer.confirmArmed ? armedStyle : null,
            icon: const Icon(Icons.stop),
            label: Text(stopLabel),
          ),
      ],
      TimerRun.paused => [
        FilledButton.icon(
          onPressed: cubit.resume,
          icon: const Icon(Icons.play_arrow),
          label: const Text(S.resume),
        ),
        const SizedBox(width: 12),
        if (!timer.isBreak) ...[
          FilledButton.tonalIcon(
            onPressed: () => cubit.doneEarly(),
            icon: const Icon(Icons.check),
            label: const Text(S.doneEarly),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _stopWithNote(context),
            icon: const Icon(Icons.stop),
            label: const Text(S.stop),
          ),
        ],
      ],
    };
  }
}

/// Карточка «СЕЙЧАС» — одна задача в работе (WIP = 1).
class _NowCard extends StatelessWidget {
  const _NowCard({required this.task});

  final PomoTask? task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = task;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: current == null
            ? Colors.transparent
            : theme.colorScheme.surfaceContainerLowest,
        border: Border.all(
          color: current == null
              ? theme.colorScheme.outlineVariant
              : theme.colorScheme.primary.withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: current == null
            ? null
            : [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          Text(
            S.nowLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          if (current == null)
            Text(
              S.nowEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (current.frog) const Text('🐸 '),
                Flexible(
                  child: Text(
                    current.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                CategoryChip(current.category),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Запланировано
// ---------------------------------------------------------------------------

class _TodoSection extends StatelessWidget {
  const _TodoSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksState = context.watch<TasksCubit>().state;
    final timer = context.watch<TimerCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;

    if (tasksState.status == TasksStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tasksState.status == TasksStatus.failure) {
      return ErrorPane(
        message: tasksState.error,
        onRetry: () => context.read<TasksCubit>().load(),
      );
    }

    final visible = tasksState.visibleTodo;
    final scheme = settings.scheme;
    final totalPomos = visible.fold(
      0,
      (sum, t) => sum + t.pomos(scheme.pomodoro),
    );
    // Идущий помидор списывается с реальной первой задачи — при фильтре
    // категории первая видимая может быть другой, тогда carry не применяем.
    final carryFirst =
        visible.isNotEmpty &&
        tasksState.todo.isNotEmpty &&
        identical(visible.first, tasksState.todo.first);
    final forecast = _forecast(visible, timer, scheme, carryFirst);

    return SectionCard(
      title:
          '${S.planned} · $totalPomos / ${formatMinutes(totalPomos * scheme.pomodoro)}',
      trailing: _ListGear(
        items: [
          _GearItem(
            label: S.tasksTopLabel,
            checked: settings.tasksTop,
            onTap: () => context.read<SettingsCubit>().update(
              settings.copyWith(tasksTop: !settings.tasksTop),
            ),
          ),
          _GearItem(
            label: S.completeRemoveLabel,
            checked: settings.completeRemove,
            onTap: () => context.read<SettingsCubit>().update(
              settings.copyWith(completeRemove: !settings.completeRemove),
            ),
          ),
          _GearItem(
            label: S.clearList,
            onTap: () async {
              if (await _confirmClear(context)) {
                if (context.mounted) {
                  await context.read<TasksCubit>().clearTodo();
                }
              }
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AddTaskForm(
            onSubmit: (category, text) => context.read<TasksCubit>().add(
              text,
              fallbackCategory: category,
            ),
            onSubmitInbox: (category, text) => context.read<TasksCubit>().add(
              text,
              fallbackCategory: category,
              toPlanner: true,
            ),
            plannerButton: true,
          ),
          const SizedBox(height: 8),
          if (tasksState.todo.length > 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                S.dayOverload,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(S.emptyPlanned, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(S.emptyPlannedHint, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          else ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Своя ручка слева: стандартная накладывается на меню ⋮.
              buildDefaultDragHandles: false,
              itemCount: visible.length,
              onReorderItem: (oldIndex, newIndex) {
                // identical — после split в списке бывают равные копии.
                final cubit = context.read<TasksCubit>();
                final from = cubit.todoIndexOf(visible[oldIndex]);
                final target = cubit.todoIndexOf(
                  visible[newIndex.clamp(0, visible.length - 1)],
                );
                if (from >= 0 && target >= 0) {
                  cubit.reorder(from, target);
                }
              },
              itemBuilder: (context, i) {
                final task = visible[i];
                return _TaskRow(
                  key: ObjectKey(task),
                  task: task,
                  viewIndex: i,
                  endTime: forecast.taskEnds.length > i
                      ? forecast.taskEnds[i]
                      : null,
                  pomodoroMinutes: scheme.pomodoro,
                  timeFmt: settings.timeFmt,
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${S.finishTime} · ${formatClock(forecast.finish, settings.timeFmt)}',
                  style: theme.textTheme.titleSmall,
                ),
                if (forecast.nextLongBreak != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    '${S.nextLongBreak} · ${formatClock(forecast.nextLongBreak!, settings.timeFmt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const Divider(height: 24),
          _CategoryRow(
            counters: tasksState.categoryCounters(scheme.pomodoro),
            selected: tasksState.categoryFilter,
            onSelect: (c) => context.read<TasksCubit>().setCategoryFilter(c),
          ),
          const SizedBox(height: 4),
          Text(
            S.hintTasks,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Прогноз: перерывы учитываются, текущий помидор — первый помидор
  /// первой задачи, тип перерыва — по сквозному счётчику серии.
  static ({List<DateTime> taskEnds, DateTime finish, DateTime? nextLongBreak})
  _forecast(
    List<PomoTask> tasks,
    TimerState timer,
    TimerScheme scheme,
    bool carryFirst,
  ) {
    final now = DateTime.now();
    // База — конец текущей фазы таймера.
    final base = now.add(Duration(seconds: timer.remaining));
    var cursor = base;
    var series = timer.series;
    // Идущий (или взведённый) помидор — первый помидор первой задачи.
    var carry = carryFirst && timer.mode == TimerMode.pomodoro;
    if (carry) series += 1;
    final taskEnds = <DateTime>[];
    for (final task in tasks) {
      var pomos = task.pomos(scheme.pomodoro);
      if (carry) {
        pomos -= 1;
        carry = false;
      }
      for (var p = 0; p < pomos; p++) {
        // Перерыв после предыдущего помидора: длинный на границе серии.
        cursor = cursor.add(
          Duration(
            minutes: series > 0 && series % scheme.longEvery == 0
                ? scheme.longBreak
                : scheme.shortBreak,
          ),
        );
        cursor = cursor.add(Duration(minutes: scheme.pomodoro));
        series += 1;
      }
      taskEnds.add(cursor);
    }
    final finish = taskEnds.isEmpty ? base : taskEnds.last;
    // Следующий длинный перерыв: после скольких ещё помидоров серия кратна N.
    var s = timer.series + (timer.mode == TimerMode.pomodoro ? 1 : 0);
    var t = base;
    while (s == 0 || s % scheme.longEvery != 0) {
      t = t.add(Duration(minutes: scheme.shortBreak + scheme.pomodoro));
      s += 1;
    }
    DateTime? nextLong = t;
    if (nextLong.isAfter(finish)) nextLong = null;
    return (taskEnds: taskEnds, finish: finish, nextLongBreak: nextLong);
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.viewIndex,
    required this.endTime,
    required this.pomodoroMinutes,
    required this.timeFmt,
    super.key,
  });

  final PomoTask task;

  /// Позиция в видимом списке — для ручки перетаскивания.
  final int viewIndex;
  final DateTime? endTime;
  final int pomodoroMinutes;
  final TimeFmt timeFmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TasksCubit>();
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minLeadingWidth: 20,
      leading: ReorderableDragStartListener(
        index: viewIndex,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Icon(
            Icons.drag_indicator,
            size: 16,
            color: theme.colorScheme.outline,
          ),
        ),
      ),
      title: Row(
        children: [
          if (task.frog) const Text('🐸 '),
          CategoryChip(task.category, onTap: () => _editTask(context, cubit)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              task.description,
              style: task.frog
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
          if (task.week)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.star,
                size: 14,
                color: theme.colorScheme.tertiary,
              ),
            ),
        ],
      ),
      onTap: () => _editTask(context, cubit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (endTime != null)
            Tooltip(
              message: S.finishTime,
              child: Text(
                formatClock(endTime!, timeFmt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Tooltip(
            message:
                '${task.durationMinutes}м · клик +1 🍅, Alt-клик −1, Shift ×4',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                // Индекс в момент клика: список мог сдвинуться.
                final index = cubit.todoIndexOf(task);
                if (index < 0) return;
                final shift = HardwareKeyboard.instance.isShiftPressed;
                final count = shift ? 4 : 1;
                if (HardwareKeyboard.instance.isAltPressed) {
                  cubit.minus(index, count: count);
                } else {
                  cubit.plus(index, count: count);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${task.pomos(pomodoroMinutes)}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
          ),
          _TaskMenu(task: task),
        ],
      ),
    );
  }

  void _editTask(BuildContext context, TasksCubit cubit) {
    showEditDialog(
      context,
      title: S.editTask,
      fields: {
        S.categoryHint: task.category,
        S.descriptionHint: task.description,
      },
    ).then((values) {
      if (values == null) return;
      final index = cubit.todoIndexOf(task);
      if (index < 0) return;
      cubit.edit(
        index,
        category: values[S.categoryHint],
        description: values[S.descriptionHint],
      );
    });
  }
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({required this.task});

  final PomoTask task;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TasksCubit>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        // Индекс в момент выбора: пока меню было открыто, помидор мог
        // дотикать и сдвинуть список.
        final index = cubit.todoIndexOf(task);
        if (index < 0) return;
        switch (value) {
          case 'plus':
            cubit.plus(index);
          case 'minus':
            cubit.minus(index);
          case 'done':
            cubit.markDone(index);
          case 'doneAll':
            cubit.markDone(index, whole: true);
          case 'split':
            cubit.split(index);
          case 'merge':
            cubit.merge(index);
          case 'inbox':
            cubit.postpone(index, PlannerTab.inbox);
          case 'tomorrow':
            cubit.postpone(index, PlannerTab.tomorrow);
          case 'later':
            cubit.postpone(index, PlannerTab.later);
          case 'delete':
            cubit.removeAt(index);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'plus', child: Text(S.menuAddPomo)),
        PopupMenuItem(
          value: 'minus',
          enabled: task.durationMinutes > 1,
          child: const Text(S.menuRemovePomo),
        ),
        const PopupMenuItem(value: 'done', child: Text(S.menuMarkDone)),
        const PopupMenuItem(value: 'doneAll', child: Text(S.menuCloseWhole)),
        const PopupMenuItem(value: 'split', child: Text(S.menuSplit)),
        const PopupMenuItem(value: 'merge', child: Text(S.menuMerge)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'inbox', child: Text('↩ ${S.menuToInbox}')),
        const PopupMenuItem(value: 'tomorrow', child: Text(S.menuToTomorrow)),
        const PopupMenuItem(value: 'later', child: Text(S.menuToLater)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text(S.delete)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Сделано
// ---------------------------------------------------------------------------

class _DoneSection extends StatelessWidget {
  const _DoneSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journal = context.watch<JournalCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;
    final log = journal.log;

    if (journal.status == JournalStatus.loading || log == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (journal.status == JournalStatus.failure) {
      return ErrorPane(
        message: journal.error,
        onRetry: () => context.read<JournalCubit>().refresh(),
      );
    }

    final visible = journal.visible;
    // При фильтре категории позиции маркера цели не совпадают со счётчиком
    // полного журнала — маркер прячем.
    final goal = journal.categoryFilter == null ? settings.dailyGoal : 0;

    final rows = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      // Маркер цели: под ним остаётся ровно goal записей.
      if (goal > 0 && log.count >= goal && i == log.count - goal) {
        rows.add(_GoalMarker(reached: true, goal: goal));
      }
      rows.add(_DoneRow(entry: visible[i], settings: settings));
    }
    if (goal > 0 && log.count < goal) {
      rows.insert(0, _GoalMarker(reached: false, goal: goal - log.count));
    }

    return SectionCard(
      title: '${S.doneTitle} · ${log.count} / ${formatMinutes(log.minutes)}',
      trailing: _ListGear(
        items: [
          _GearItem(
            label: S.clearList,
            onTap: () async {
              if (await _confirmClear(context)) {
                if (context.mounted) {
                  await context.read<JournalCubit>().clearToday();
                }
              }
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                S.emptyDone,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ...rows,
          const Divider(height: 24),
          Text(
            '${S.focusLabel} · ${log.focus}% · ${S.delaysLabel} · '
            '${formatMinutes(log.delayMinutes)} · ${S.interruptionsLabel} · ${log.interruptions}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _CategoryRow(
            counters: journal.categoryCounters,
            selected: journal.categoryFilter,
            onSelect: (c) => context.read<JournalCubit>().setCategoryFilter(c),
          ),
        ],
      ),
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.entry, required this.settings});

  final PomoSession entry;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<JournalCubit>();
    final finish = entry.start.add(Duration(minutes: entry.minutes));
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: entry.category.isEmpty
          ? const SizedBox(width: 8)
          : CategoryChip(entry.category),
      title: Text(
        '${entry.frog ? '🐸 ' : ''}${entry.task.isEmpty ? '—' : entry.task}',
        style: theme.textTheme.bodyMedium,
      ),
      onTap: () => _edit(context, cubit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.manual)
            Tooltip(
              message: S.manualMark,
              child: Icon(
                Icons.touch_app_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            '${formatMinutes(entry.minutes)} · ${formatClock(finish, settings.timeFmt)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (value) {
              switch (value) {
                case 'repeat':
                  context.read<TasksCubit>().add(
                    entry.task,
                    fallbackCategory: entry.category,
                  );
                case 'fill':
                  cubit.fillBlanks(entry);
                case 'delete':
                  cubit.deleteEntry(entry);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'repeat', child: Text(S.menuRepeat)),
              const PopupMenuItem(value: 'fill', child: Text(S.menuFillBlanks)),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text(S.delete)),
            ],
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, JournalCubit cubit) {
    showEditDialog(
      context,
      title: S.doneTitle,
      fields: {
        S.categoryHint: entry.category,
        S.descriptionHint: entry.task,
        'Минуты': '${entry.minutes}',
      },
    ).then((values) {
      if (values == null) return;
      cubit.editEntry(
        entry,
        category: values[S.categoryHint],
        task: values[S.descriptionHint],
        minutes: int.tryParse(values['Минуты'] ?? '') ?? entry.minutes,
      );
    });
  }
}

class _GoalMarker extends StatelessWidget {
  const _GoalMarker({required this.reached, required this.goal});

  final bool reached;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = reached
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.star, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  reached
                      ? '${S.goalLine} · $goal'
                      : '${S.goalLine} · ${S.goalLeft} $goal',
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Общие детали страницы
// ---------------------------------------------------------------------------

class _GearItem {
  const _GearItem({required this.label, required this.onTap, this.checked});

  final String label;
  final VoidCallback onTap;
  final bool? checked;
}

class _ListGear extends StatelessWidget {
  const _ListGear({required this.items});

  final List<_GearItem> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: S.listSettings,
      icon: const Icon(Icons.settings_outlined, size: 18),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (context) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                if (items[i].checked != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      items[i].checked!
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                  ),
                Text(items[i].label),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.counters,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counters;
  final String? selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (counters.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(S.categories, style: theme.textTheme.labelMedium),
        for (final entry in counters.entries)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(entry.key),
            child: Opacity(
              opacity: selected == null || selected == entry.key ? 1 : 0.45,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryChip(entry.key),
                  Text(' · ${entry.value}', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Форма добавления: дропдаун категории + умный ввод.
/// Enter/Добавить — в «Сегодня»; кнопка-инбокс — мгновенный захват.
class _AddTaskForm extends StatefulWidget {
  const _AddTaskForm({
    required this.onSubmit,
    this.onSubmitInbox,
    this.plannerButton = false,
  });

  final void Function(String category, String text) onSubmit;
  final void Function(String category, String text)? onSubmitInbox;
  final bool plannerButton;

  @override
  State<_AddTaskForm> createState() => _AddTaskFormState();
}

class _AddTaskFormState extends State<_AddTaskForm> {
  final _text = TextEditingController();
  String _category = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_text.text.trim().isEmpty) return;
    widget.onSubmit(_category, _text.text);
    _text.clear();
  }

  void _submitInbox() {
    if (_text.text.trim().isEmpty) return;
    widget.onSubmitInbox?.call(_category, _text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context
        .watch<SettingsCubit>()
        .state
        .settings
        .categories
        .keys
        .toList();
    if (_category.isEmpty && categories.isNotEmpty) {
      _category = categories.first;
    }
    return Row(
      children: [
        DropdownMenu<String>(
          initialSelection: _category,
          width: 140,
          requestFocusOnTap: false,
          label: const Text(S.categoryHint),
          dropdownMenuEntries: [
            for (final c in categories) DropdownMenuEntry(value: c, label: c),
          ],
          onSelected: (value) => setState(() => _category = value ?? _category),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _text,
            decoration: const InputDecoration(
              hintText: S.descriptionHint,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: _submit, child: const Text(S.add)),
        if (widget.onSubmitInbox != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: S.toInbox,
            icon: const Icon(Icons.move_to_inbox_outlined, size: 20),
            onPressed: _submitInbox,
          ),
        ],
        if (widget.plannerButton) ...[
          const SizedBox(width: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.inbox_outlined, size: 16),
            label: const Text(S.planner),
            onPressed: () => showPlannerDialog(context),
          ),
        ],
      ],
    );
  }
}

/// Подтверждение необратимой очистки списка.
Future<bool> _confirmClear(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(S.clearList),
      content: const Text(S.confirmClear),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(S.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Простой диалог редактирования пар «метка → значение».
Future<Map<String, String>?> showEditDialog(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
}) {
  final controllers = {
    for (final e in fields.entries) e.key: TextEditingController(text: e.value),
  };
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in controllers.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: e.value,
                decoration: InputDecoration(
                  labelText: e.key,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(S.close),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop({
            for (final e in controllers.entries) e.key: e.value.text.trim(),
          }),
          child: const Text(S.save),
        ),
      ],
    ),
  ).whenComplete(() {
    for (final c in controllers.values) {
      c.dispose();
    }
  });
}
