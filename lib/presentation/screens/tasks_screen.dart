import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/sprint_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../widgets/common.dart';

/// Экран «Задачи»: quick-add + сворачиваемые группы (Сегодня и корзины
/// планировщика одним потоком) + «Сделано за неделю». Тот же TasksCubit,
/// что у таймера и диалога планировщика, — рассинхрона нет.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  /// Сигнал «сфокусируй поле ввода» (Ctrl+N из HomeShell).
  static final ValueNotifier<int> focusSignal = ValueNotifier(0);

  static void requestQuickAddFocus() => focusSignal.value++;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _text = TextEditingController();
  final _inputFocus = FocusNode();
  String _category = '';

  @override
  void initState() {
    super.initState();
    TasksScreen.focusSignal.addListener(_onFocusSignal);
  }

  @override
  void dispose() {
    TasksScreen.focusSignal.removeListener(_onFocusSignal);
    _text.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onFocusSignal() => _inputFocus.requestFocus();

  // -- добавление -------------------------------------------------------------

  void _submitInbox() {
    // Как в кубите: «#кат ~3» без описания — не задача; поле не очищаем.
    if (parseSmartInput(_text.text).description.isEmpty) return;
    context.read<TasksCubit>().add(
      _text.text,
      fallbackCategory: _category,
      toPlanner: true,
    );
    _text.clear();
    _inputFocus.requestFocus();
  }

  void _submitToday() {
    if (parseSmartInput(_text.text).description.isEmpty) return;
    context.read<TasksCubit>().add(_text.text, fallbackCategory: _category);
    _text.clear();
    _inputFocus.requestFocus();
  }

  // -- сворачивание -----------------------------------------------------------

  void _toggleGroup(String key) {
    final cubit = context.read<SettingsCubit>();
    final settings = cubit.state.settings;
    final set = {...settings.collapsedGroups};
    if (!set.remove(key)) set.add(key);
    cubit.update(settings.copyWith(collapsedGroups: set.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final tasksState = context.watch<TasksCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;
    final sprint = context.watch<SprintCubit>().state.sprint;

    if (tasksState.status == TasksStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tasksState.status == TasksStatus.failure) {
      return ErrorPane(
        message: tasksState.error,
        onRetry: () => context.read<TasksCubit>().load(),
      );
    }

    final collapsed = settings.collapsedGroups.toSet();
    final pomodoro = settings.scheme.pomodoro;
    final now = DateTime.now();
    // Корзины: пары (реальный индекс в planner, задача).
    final buckets = {
      for (final tab in PlannerTab.values) tab: <(int, PomoTask)>[],
    };
    for (var i = 0; i < tasksState.planner.length; i++) {
      final task = tasksState.planner[i];
      buckets[task.tab(now)]!.add((i, task));
    }

    Widget todayCard() => _TodayGroup(
      todo: tasksState.todo,
      pomodoro: pomodoro,
      collapsed: collapsed.contains('today'),
      onToggle: () => _toggleGroup('today'),
    );

    List<Widget> bucketCards() => [
      for (final tab in PlannerTab.values) ...[
        _BucketGroup(
          tab: tab,
          items: buckets[tab]!,
          pomodoro: pomodoro,
          collapsed: collapsed.contains(tab.name),
          onToggle: () => _toggleGroup(tab.name),
        ),
        const SizedBox(height: 12),
      ],
      _DoneWeekGroup(
        lines: sprint?.doneWeek ?? const [],
        collapsed: collapsed.contains('doneWeek'),
        onToggle: () => _toggleGroup('doneWeek'),
      ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: _quickAdd(context),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Широкое окно: «Сегодня» слева, корзины справа. Узкое (и в
              // будущем телефон) — один столбец, тот же набор виджетов.
              final wide = constraints.maxWidth >= 1000;
              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          todayCard(),
                          const SizedBox(height: 12),
                          ...bucketCards(),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 6, 24),
                      child: todayCard(),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(6, 8, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: bucketCards(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quickAdd(BuildContext context) {
    final theme = Theme.of(context);
    final categories = context
        .watch<SettingsCubit>()
        .state
        .settings
        .categories
        .keys
        .toList();
    // Валидируем: выбранную категорию могли удалить в настройках.
    if ((_category.isEmpty || !categories.contains(_category)) &&
        categories.isNotEmpty) {
      _category = categories.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DropdownMenu<String>(
              initialSelection: _category,
              width: 140,
              requestFocusOnTap: false,
              label: Text(S.categoryHint),
              dropdownMenuEntries: [
                for (final c in categories)
                  DropdownMenuEntry(value: c, label: c),
              ],
              onSelected: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): _submitToday,
                  const SingleActivator(
                    LogicalKeyboardKey.numpadEnter,
                    control: true,
                  ): _submitToday,
                },
                child: TextField(
                  controller: _text,
                  focusNode: _inputFocus,
                  decoration: InputDecoration(
                    hintText: S.descriptionHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitInbox(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _submitInbox, child: Text(S.add)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          S.quickAddHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Группы
// ---------------------------------------------------------------------------

/// Карточка-группа с кликабельным заголовком и шевроном.
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.counter,
    required this.collapsed,
    required this.onToggle,
    required this.child,
    this.icon,
  });

  final String title;
  final String counter;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        counter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) child,
          ],
        ),
      ),
    );
  }
}

/// «Сегодня»: NOW-подсветка первой задачи, drag-сортировка, 🐸/⭐ на строке.
class _TodayGroup extends StatelessWidget {
  const _TodayGroup({
    required this.todo,
    required this.pomodoro,
    required this.collapsed,
    required this.onToggle,
  });

  final List<PomoTask> todo;
  final int pomodoro;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPomos = todo.fold(0, (sum, t) => sum + t.pomos(pomodoro));
    final counter = todo.isEmpty
        ? '0'
        : '${todo.length} · $totalPomos 🍅 / '
              '${formatMinutesUi(totalPomos * pomodoro)}';
    return _Group(
      title: S.periodToday,
      counter: counter,
      collapsed: collapsed,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (todo.length > 3)
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
          if (todo.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(S.emptyPlanned, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(S.emptyPlannedHint, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: todo.length,
              onReorderItem: (oldIndex, newIndex) {
                // identical — после split в списке бывают равные копии.
                final cubit = context.read<TasksCubit>();
                final from = cubit.todoIndexOf(todo[oldIndex]);
                final target = cubit.todoIndexOf(
                  todo[newIndex.clamp(0, todo.length - 1)],
                );
                if (from >= 0 && target >= 0) cubit.reorder(from, target);
              },
              itemBuilder: (context, i) => _TodayRow(
                key: ObjectKey(todo[i]),
                task: todo[i],
                viewIndex: i,
                pomodoro: pomodoro,
                isNow: i == 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.task,
    required this.viewIndex,
    required this.pomodoro,
    required this.isNow,
    super.key,
  });

  final PomoTask task;
  final int viewIndex;
  final int pomodoro;
  final bool isNow;

  void _edit(BuildContext context, TasksCubit cubit) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TasksCubit>();
    // Индекс — в момент действия: пока экран открыт, список мог сдвинуться.
    void act(void Function(int index) fn) {
      final i = cubit.todoIndexOf(task);
      if (i >= 0) fn(i);
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minLeadingWidth: 20,
      shape: isNow
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.primary, width: 1),
            )
          : null,
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
          CategoryChip(task.category, onTap: () => _edit(context, cubit)),
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
          if (isNow)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  S.nowLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      onTap: () => _edit(context, cubit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FrogToggle(active: task.frog, onTap: () => act(cubit.toggleFrog)),
          StarToggle(active: task.week, onTap: () => act(cubit.toggleWeek)),
          const SizedBox(width: 4),
          PomosBadge(task: task, pomodoro: pomodoro),
          TaskMenu(task: task),
        ],
      ),
    );
  }
}

/// Корзина планировщика: Входящие / Завтра / Эта неделя / Позже.
class _BucketGroup extends StatelessWidget {
  const _BucketGroup({
    required this.tab,
    required this.items,
    required this.pomodoro,
    required this.collapsed,
    required this.onToggle,
  });

  final PlannerTab tab;

  /// Пары (реальный индекс в planner, задача).
  final List<(int, PomoTask)> items;
  final int pomodoro;
  final bool collapsed;
  final VoidCallback onToggle;

  static IconData _icon(PlannerTab tab) => switch (tab) {
    PlannerTab.inbox => Icons.inbox_outlined,
    PlannerTab.tomorrow => Icons.wb_sunny_outlined,
    PlannerTab.week => Icons.date_range_outlined,
    PlannerTab.later => Icons.schedule_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPomos = items.fold(0, (sum, e) => sum + e.$2.pomos(pomodoro));
    return _Group(
      title: plannerTabLabel(tab),
      counter: items.isEmpty ? '0' : '${items.length} · $totalPomos 🍅',
      collapsed: collapsed,
      onToggle: onToggle,
      icon: _icon(tab),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.emptyBucket,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) {
                final cubit = context.read<TasksCubit>();
                final from = cubit.plannerIndexOf(items[oldIndex].$2);
                final target = cubit.plannerIndexOf(
                  items[newIndex.clamp(0, items.length - 1)].$2,
                );
                if (from >= 0 && target >= 0) {
                  cubit.plannerReorder(from, target);
                }
              },
              itemBuilder: (context, i) => _BucketRow(
                key: ObjectKey(items[i].$2),
                task: items[i].$2,
                viewIndex: i,
                bucket: tab,
                pomodoro: pomodoro,
              ),
            ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.task,
    required this.viewIndex,
    required this.bucket,
    required this.pomodoro,
    super.key,
  });

  final PomoTask task;
  final int viewIndex;
  final PlannerTab bucket;
  final int pomodoro;

  void _edit(BuildContext context, TasksCubit cubit) {
    showEditDialog(
      context,
      title: S.editTask,
      fields: {
        S.categoryHint: task.category,
        S.descriptionHint: task.description,
      },
    ).then((values) {
      if (values == null) return;
      final index = cubit.plannerIndexOf(task);
      if (index < 0) return;
      cubit.plannerEdit(
        index,
        category: values[S.categoryHint],
        description: values[S.descriptionHint],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TasksCubit>();
    void act(void Function(int index) fn) {
      final i = cubit.plannerIndexOf(task);
      if (i >= 0) fn(i);
    }

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
          CategoryChip(task.category, onTap: () => _edit(context, cubit)),
          const SizedBox(width: 8),
          Flexible(child: Text(task.description)),
          if (task.due != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '📅 ${task.due!.day.toString().padLeft(2, '0')}.'
                '${task.due!.month.toString().padLeft(2, '0')}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      onTap: () => _edit(context, cubit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarToggle(
            active: task.week,
            onTap: () => act((i) => cubit.toggleWeek(i, inPlanner: true)),
          ),
          const SizedBox(width: 4),
          PomosBadge(task: task, pomodoro: pomodoro, inPlanner: true),
          IconButton(
            tooltip: S.toToday,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.today, size: 16),
            onPressed: () => act(cubit.plannerToToday),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (value) {
              if (value == 'delete') {
                final i = cubit.plannerIndexOf(task);
                if (i < 0) return;
                cubit.plannerRemove(i);
                showUndoSnack(
                  context,
                  onUndo: () => cubit.insertPlannerAt(i, task),
                );
                return;
              }
              final tab = PlannerTab.values.asNameMap()[value];
              if (tab != null) act((i) => cubit.plannerMove(i, tab));
            },
            itemBuilder: (context) => [
              for (final tab in PlannerTab.values)
                if (tab != bucket)
                  PopupMenuItem(
                    value: tab.name,
                    child: Text('→ ${plannerTabLabel(tab)}'),
                  ),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text(S.delete)),
            ],
          ),
        ],
      ),
    );
  }
}

/// «Сделано за неделю»: закрытые ⭐-задачи спринта, только чтение.
class _DoneWeekGroup extends StatelessWidget {
  const _DoneWeekGroup({
    required this.lines,
    required this.collapsed,
    required this.onToggle,
  });

  final List<String> lines;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Group(
      title: S.doneWeekTitle,
      counter: '${lines.length}',
      collapsed: collapsed,
      onToggle: onToggle,
      icon: Icons.check_circle_outline,
      child: lines.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.emptyBucket,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Бейдж помидоров: на «Сегодня» кликабельный (+1 / Alt −1 / Shift ×4).
class PomosBadge extends StatelessWidget {
  const PomosBadge({
    required this.task,
    required this.pomodoro,
    this.inPlanner = false,
    super.key,
  });

  final PomoTask task;
  final int pomodoro;
  final bool inPlanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('${task.pomos(pomodoro)}', style: theme.textTheme.labelLarge),
    );
    if (inPlanner) {
      return Tooltip(
        message: formatMinutesUi(task.durationMinutes),
        child: badge,
      );
    }
    final cubit = context.read<TasksCubit>();
    return Tooltip(
      message: S.pomoClickHint(task.durationMinutes),
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
        child: badge,
      ),
    );
  }
}
