import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/journal_cubit.dart';
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
      _DoneTodayGroup(
        sessions: context.watch<JournalCubit>().state.visible,
        timeFmt: settings.timeFmt,
        collapsed: collapsed.contains('doneToday'),
        onToggle: () => _toggleGroup('doneToday'),
      ),
      const SizedBox(height: 12),
      _DoneWeekGroup(
        lines: sprint?.doneWeek ?? const [],
        collapsed: collapsed.contains('doneWeek'),
        onToggle: () => _toggleGroup('doneWeek'),
      ),
      const SizedBox(height: 12),
      _TrashGroup(
        trash: tasksState.trash,
        collapsed: collapsed.contains('trash'),
        onToggle: () => _toggleGroup('trash'),
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
    final picker = DropdownMenu<String>(
      initialSelection: _category,
      width: 140,
      requestFocusOnTap: false,
      label: Text(S.categoryHint),
      dropdownMenuEntries: [
        for (final c in categories) DropdownMenuEntry(value: c, label: c),
      ],
      onSelected: (v) => setState(() => _category = v ?? _category),
    );
    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _submitToday,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _submitToday,
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
    );
    final button = FilledButton.tonal(
      onPressed: _submitInbox,
      child: Text(S.add),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // На телефоне в одну строку полю ввода остаётся ~90dp — переносим
        // категорию и кнопку под него.
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 460
              ? Column(
                  children: [
                    field,
                    const SizedBox(height: 8),
                    Row(children: [picker, const Spacer(), button]),
                  ],
                )
              : Row(
                  children: [
                    picker,
                    const SizedBox(width: 8),
                    Expanded(child: field),
                    const SizedBox(width: 8),
                    button,
                  ],
                ),
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

/// Тесно ли строке списка. Считается по ДОСТУПНОЙ ширине, а не по ширине
/// экрана: на десктопе колонка «Сегодня» шириной 460 так же тесна, как
/// телефон, и раскладка там должна быть та же.
bool _isNarrowRow(BoxConstraints c) => c.maxWidth < 520;

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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
    showTaskEditDialog(
      context,
      title: S.editTask,
      category: task.category,
      description: task.description,
    ).then((r) {
      if (r == null) return;
      final index = cubit.todoIndexOf(task);
      if (index < 0) return;
      cubit.edit(
        index,
        category: r.category.isEmpty ? null : r.category,
        description: r.description.isEmpty ? null : r.description,
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

    final chip = CategoryChip(
      task.category,
      onTap: () => _edit(context, cubit),
    );
    final description = Text(
      task.description,
      style: task.frog
          ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
          : theme.textTheme.bodyMedium,
    );
    const nowPad = EdgeInsets.only(left: 6);
    final nowBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
    );

    final frog = FrogToggle(
      active: task.frog,
      onTap: () => act(cubit.toggleFrog),
    );
    final star = StarToggle(
      active: task.week,
      onTap: () => act(cubit.toggleWeek),
    );

    // Раскладка по доступной ширине, а не по ширине экрана: на десктопе
    // колонка «Сегодня» такая же тесная, как телефон.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = _isNarrowRow(constraints);
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
          // На телефоне ручки нет: список и так тянется долгим нажатием, а
          // каждый лишний элемент отъедает ширину у описания.
          leading: narrow
              ? null
              : ReorderableDragStartListener(
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
          // На телефоне описание занимает всю строку, а чип категории и «СЕЙЧАС»
          // уезжают под него: в один ряд с кнопками описанию оставалось ~40dp,
          // и текст рассыпался по букве на строку.
          title: narrow
              ? description
              : Row(
                  children: [
                    chip,
                    const SizedBox(width: 8),
                    Flexible(child: description),
                    if (isNow) Padding(padding: nowPad, child: nowBadge),
                  ],
                ),
          subtitle: narrow
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  // Wrap: длинная категория вместе с меткой «сейчас» в одну
                  // строку не помещается.
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      chip,
                      if (isNow) nowBadge,
                      // Переключатели 🐸/⭐ на телефоне живут здесь: справа они
                      // вместе со счётчиком и меню не оставляли описанию места.
                      frog,
                      star,
                    ],
                  ),
                )
              : null,
          onTap: () => _edit(context, cubit),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!narrow) ...[frog, star, const SizedBox(width: 4)],
              PomosBadge(task: task, pomodoro: pomodoro),
              TaskMenu(task: task),
            ],
          ),
        );
      },
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
    PlannerTab.due => Icons.event_available_outlined,
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
    showTaskEditDialog(
      context,
      title: S.editTask,
      category: task.category,
      description: task.description,
    ).then((r) {
      if (r == null) return;
      final index = cubit.plannerIndexOf(task);
      if (index < 0) return;
      cubit.plannerEdit(
        index,
        category: r.category.isEmpty ? null : r.category,
        description: r.description.isEmpty ? null : r.description,
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

    final chip = CategoryChip(
      task.category,
      onTap: () => _edit(context, cubit),
    );
    const duePad = EdgeInsets.only(left: 8);
    final due = task.due == null
        ? null
        : Text(
            '📅 ${task.due!.day.toString().padLeft(2, '0')}.'
            '${task.due!.month.toString().padLeft(2, '0')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    final star = StarToggle(
      active: task.week,
      onTap: () => act((i) => cubit.toggleWeek(i, inPlanner: true)),
    );

    // См. _TodayRow: раскладка по доступной ширине, а не по ширине экрана.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = _isNarrowRow(constraints);
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          minLeadingWidth: 20,
          // См. _TodayRow: на телефоне ручки нет, место уходит описанию.
          leading: narrow
              ? null
              : ReorderableDragStartListener(
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
          // См. _TodayRow: на телефоне описание получает всю строку целиком.
          title: narrow
              ? Text(task.description)
              : Row(
                  children: [
                    chip,
                    const SizedBox(width: 8),
                    Flexible(child: Text(task.description)),
                    if (due != null) Padding(padding: duePad, child: due),
                  ],
                ),
          subtitle: narrow
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  // Wrap: длинная категория вместе с датой в одну строку
                  // не помещается.
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    // ⭐ на телефоне здесь: справа он вместе со счётчиком,
                    // кнопкой «в сегодня» и меню не оставлял описанию места.
                    children: [chip, ?due, star],
                  ),
                )
              : null,
          onTap: () => _edit(context, cubit),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!narrow) ...[star, const SizedBox(width: 4)],
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
                    // plannerRemove пишет в корзину синхронно — уже здесь.
                    final trash = cubit.state.trash;
                    if (trash.isNotEmpty) {
                      showUndoSnack(
                        context,
                        onUndo: () => cubit.restoreFromTrash(trash.first),
                      );
                    }
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
      },
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

/// «Сделано сегодня»: записи журнала за текущий логический день — и от
/// таймера, и от ручной отметки. Только чтение; правки — на «Таймере».
class _DoneTodayGroup extends StatelessWidget {
  const _DoneTodayGroup({
    required this.sessions,
    required this.timeFmt,
    required this.collapsed,
    required this.onToggle,
  });

  final List<PomoSession> sessions;
  final TimeFmt timeFmt;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Group(
      title: S.doneTodayTitle,
      counter: '${sessions.length}',
      collapsed: collapsed,
      onToggle: onToggle,
      icon: Icons.task_alt,
      child: sessions.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.doneTodayEmpty,
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
                  for (final s in sessions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${formatClock(s.start, timeFmt)} · '
                        '${s.task.isEmpty ? S.noDescription : s.task}'
                        '${s.category.isEmpty ? '' : ' #${s.category}'}'
                        ' · ${s.minutes} ${S.minShort}',
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

/// Корзина: последние удалённые задачи (сессия), каждую можно вернуть.
class _TrashGroup extends StatelessWidget {
  const _TrashGroup({
    required this.trash,
    required this.collapsed,
    required this.onToggle,
  });

  final List<TrashedTask> trash;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Group(
      title: S.trashTitle,
      counter: '${trash.length}',
      collapsed: collapsed,
      onToggle: onToggle,
      icon: Icons.delete_outline,
      child: trash.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.trashEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (final entry in trash)
                  ListTile(
                    // identityHashCode, не ObjectKey: TrashedTask — Equatable,
                    // два структурно одинаковых удаления не должны схлопнуться.
                    key: ValueKey(identityHashCode(entry)),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: CategoryChip(entry.task.category),
                    title: Text(
                      entry.task.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: S.undo,
                      icon: const Icon(Icons.restore, size: 18),
                      onPressed: () =>
                          context.read<TasksCubit>().restoreFromTrash(entry),
                    ),
                  ),
              ],
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


  /// Шаг оценки. Индекс берём в момент нажатия: список мог сдвинуться.
  void _step(TasksCubit cubit, {required bool add}) {
    final index = cubit.todoIndexOf(task);
    if (index < 0) return;
    // Shift меняет только величину шага, но не направление — залипший Shift
    // задачу потерять не может.
    final count = HardwareKeyboard.instance.isShiftPressed ? 4 : 1;
    if (add) {
      cubit.plus(index, count: count);
    } else {
      cubit.minus(index, count: count);
    }
  }

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
        // Вычитание — правый клик / долгое нажатие, а не Alt: глобальное
        // состояние клавиатуры залипает после Alt+Tab, и обычный клик по
        // цифре начинал вычитать вместо прибавления.
        onTap: () => _step(cubit, add: true),
        onSecondaryTap: () => _step(cubit, add: false),
        onLongPress: () => _step(cubit, add: false),
        child: badge,
      ),
    );
  }
}
