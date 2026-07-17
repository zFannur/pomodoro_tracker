import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../widgets/common.dart';

void showPlannerDialog(BuildContext context) {
  // Резолвим кубиты сразу — builder вызывается лениво, а к этому моменту
  // исходный context мог стать невалидным (экран за диалогом перестроился).
  final tasksCubit = context.read<TasksCubit>();
  final settingsCubit = context.read<SettingsCubit>();
  showDialog<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: tasksCubit),
        BlocProvider.value(value: settingsCubit),
      ],
      child: const _PlannerDialog(),
    ),
  );
}

/// Вкладки планировщика: «Сегодня» + четыре корзины по датам.
enum _Tab { today, inbox, tomorrow, week, later }

String _tabLabel(_Tab tab) => switch (tab) {
  _Tab.today => S.periodToday,
  _Tab.inbox => S.inbox,
  _Tab.tomorrow => S.tomorrow,
  _Tab.week => S.week,
  _Tab.later => S.later,
};

const _tabToPlanner = {
  _Tab.inbox: PlannerTab.inbox,
  _Tab.tomorrow: PlannerTab.tomorrow,
  _Tab.week: PlannerTab.week,
  _Tab.later: PlannerTab.later,
};

class _PlannerDialog extends StatefulWidget {
  const _PlannerDialog();

  @override
  State<_PlannerDialog> createState() => _PlannerDialogState();
}

class _PlannerDialogState extends State<_PlannerDialog> {
  _Tab _tab = _Tab.today;
  final _text = TextEditingController();
  String _category = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<TasksCubit>().state;
    final settings = context.watch<SettingsCubit>().state.settings;
    final categories = settings.categories.keys.toList();
    final pomodoro = settings.scheme.pomodoro;
    // Валидируем: выбранную категорию могли удалить в настройках.
    if ((_category.isEmpty || !categories.contains(_category)) &&
        categories.isNotEmpty) {
      _category = categories.first;
    }

    final now = DateTime.now();
    final counts = <_Tab, int>{_Tab.today: state.todo.length};
    for (final t in state.planner) {
      final tab = switch (t.tab(now)) {
        PlannerTab.inbox => _Tab.inbox,
        PlannerTab.tomorrow => _Tab.tomorrow,
        PlannerTab.week => _Tab.week,
        PlannerTab.later => _Tab.later,
      };
      counts[tab] = (counts[tab] ?? 0) + 1;
    }

    // Пары (индекс в своём списке, задача) для активной вкладки.
    final items = _tab == _Tab.today
        ? <(int, PomoTask)>[
            for (var i = 0; i < state.todo.length; i++) (i, state.todo[i]),
          ]
        : <(int, PomoTask)>[
            for (var i = 0; i < state.planner.length; i++)
              if (state.planner[i].tab(now) == _tabToPlanner[_tab])
                (i, state.planner[i]),
          ];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(S.planner, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: S.close,
                  ),
                ],
              ),
              Text(
                S.plannerHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Tab>(
                segments: [
                  for (final tab in _Tab.values)
                    ButtonSegment(
                      value: tab,
                      label: Text(
                        (counts[tab] ?? 0) == 0
                            ? _tabLabel(tab)
                            : '${_tabLabel(tab)} · ${counts[tab]}',
                      ),
                    ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 12),
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
                    onSelected: (v) =>
                        setState(() => _category = v ?? _category),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: InputDecoration(
                        hintText: S.descriptionHint,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: _add, child: Text(S.add)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          S.emptyBucket,
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final (index, task) = items[i];
                          return _tab == _Tab.today
                              ? _todayRow(context, theme, index, task, pomodoro)
                              : _plannerRow(
                                  context,
                                  theme,
                                  index,
                                  task,
                                  pomodoro,
                                );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Строка «Сегодня»: здесь ставятся 🐸 и ⭐.
  Widget _todayRow(
    BuildContext context,
    ThemeData theme,
    int index,
    PomoTask task,
    int pomodoro,
  ) {
    final cubit = context.read<TasksCubit>();
    // Индекс — в момент действия: пока диалог открыт, список мог сдвинуться.
    void act(void Function(int index) fn) {
      final i = cubit.todoIndexOf(task);
      if (i >= 0) fn(i);
    }

    return ListTile(
      dense: true,
      leading: CategoryChip(task.category),
      title: Text(task.description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FrogToggle(active: task.frog, onTap: () => act(cubit.toggleFrog)),
          StarToggle(active: task.week, onTap: () => act(cubit.toggleWeek)),
          const SizedBox(width: 4),
          _pomosBadge(theme, task, pomodoro),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (value) {
              switch (value) {
                case 'inbox':
                  act((i) => cubit.postpone(i, PlannerTab.inbox));
                case 'tomorrow':
                  act((i) => cubit.postpone(i, PlannerTab.tomorrow));
                case 'later':
                  act((i) => cubit.postpone(i, PlannerTab.later));
                case 'delete':
                  act(cubit.removeAt);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'inbox',
                child: Text('↩ ${S.menuToInbox}'),
              ),
              PopupMenuItem(
                value: 'tomorrow',
                child: Text(S.menuToTomorrow),
              ),
              PopupMenuItem(value: 'later', child: Text(S.menuToLater)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text(S.delete)),
            ],
          ),
        ],
      ),
    );
  }

  /// Строка корзины планировщика: ⭐ + помидоры + «в Сегодня».
  Widget _plannerRow(
    BuildContext context,
    ThemeData theme,
    int index,
    PomoTask task,
    int pomodoro,
  ) {
    final cubit = context.read<TasksCubit>();
    void act(void Function(int index) fn) {
      final i = cubit.plannerIndexOf(task);
      if (i >= 0) fn(i);
    }

    return ListTile(
      dense: true,
      leading: CategoryChip(task.category),
      title: Text(task.description),
      subtitle: task.due == null
          ? null
          : Text(
              '📅 ${task.due!.day.toString().padLeft(2, '0')}.'
              '${task.due!.month.toString().padLeft(2, '0')}',
              style: theme.textTheme.labelSmall,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarToggle(
            active: task.week,
            onTap: () => act((i) => cubit.toggleWeek(i, inPlanner: true)),
          ),
          const SizedBox(width: 4),
          _pomosBadge(theme, task, pomodoro),
          IconButton(
            tooltip: S.toToday,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.today, size: 16),
            onPressed: () => act(cubit.plannerToToday),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            onSelected: (value) {
              switch (value) {
                case 'delete':
                  act(cubit.plannerRemove);
                default:
                  final tab = PlannerTab.values.asNameMap()[value];
                  if (tab != null) act((i) => cubit.plannerMove(i, tab));
              }
            },
            itemBuilder: (context) => [
              for (final tab in PlannerTab.values)
                if (_tabToPlanner[_tab] != tab)
                  PopupMenuItem(
                    value: tab.name,
                    child: Text('→ ${_plannerTabLabel(tab)}'),
                  ),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text(S.delete)),
            ],
          ),
        ],
      ),
    );
  }

  static String _plannerTabLabel(PlannerTab tab) {
    return switch (tab) {
      PlannerTab.inbox => S.inbox,
      PlannerTab.tomorrow => S.tomorrow,
      PlannerTab.week => S.week,
      PlannerTab.later => S.later,
    };
  }

  Widget _pomosBadge(ThemeData theme, PomoTask task, int pomodoro) {
    // Те же паддинги/радиус, что у бейджа на главном экране.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${task.pomos(pomodoro)} 🍅',
        style: theme.textTheme.labelMedium,
      ),
    );
  }

  void _add() {
    if (_text.text.trim().isEmpty) return;
    final cubit = context.read<TasksCubit>();
    if (_tab == _Tab.today) {
      cubit.add(_text.text, fallbackCategory: _category);
      _text.clear();
      return;
    }
    final due = switch (_tab) {
      _Tab.today || _Tab.inbox => null,
      _Tab.tomorrow => DateTime.now().add(const Duration(days: 1)),
      _Tab.week => DateTime.now().add(const Duration(days: 2)),
      _Tab.later => DateTime.now().add(const Duration(days: 8)),
    };
    cubit.add(
      _text.text,
      fallbackCategory: _category,
      toPlanner: true,
      due: due == null ? null : DateTime(due.year, due.month, due.day),
    );
    _text.clear();
  }
}
