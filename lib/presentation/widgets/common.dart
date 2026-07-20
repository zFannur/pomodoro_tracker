import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';

/// Карточка-секция с заголовком.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Цветная плашка категории.
class CategoryChip extends StatelessWidget {
  const CategoryChip(this.category, {this.onTap, super.key});

  final String category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(category);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: chip,
    );
  }
}

/// Вертикальный столбчатый график по дням.
class DaysBarChart extends StatelessWidget {
  const DaysBarChart({
    required this.days,
    this.goal = 0,
    this.height = 120,
    super.key,
  });

  final List<DayLog> days;

  /// Дневная цель — дни с целью подсвечиваются основным цветом.
  final int goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = days.fold(1, (max, d) => d.count > max ? d.count : max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Tooltip(
                message:
                    '${day.date.day}.${day.date.month.toString().padLeft(2, '0')} — ${day.count} 🍅',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (day.count > 0)
                        Text(
                          '${day.count}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      const SizedBox(height: 2),
                      // Столбик берёт то, что осталось после подписей, а не
                      // фиксированную долю от «height − 40»: запас в 40 точек
                      // был угадан под обычный шрифт и переполнял колонку,
                      // когда подписи выше (крупный системный шрифт).
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: day.count == 0
                              ? null
                              : day.count / maxCount,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: day.count == 0 ? 3 : null,
                            decoration: BoxDecoration(
                              color: day.count == 0
                                  ? scheme.surfaceContainerHighest
                                  : (goal > 0 && day.count >= goal
                                        ? scheme.primary
                                        : scheme.primary.withValues(
                                            alpha: 0.45,
                                          )),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.date.day}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Плитка показателя.
class StatTile extends StatelessWidget {
  const StatTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // scaleDown: длинное значение ужимается, а не переполняет плитку.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Переключатель «🐸 лягушка дня» — кликается прямо на строке задачи.
class FrogToggle extends StatelessWidget {
  const FrogToggle({required this.active, required this.onTap, super.key});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? S.frogRemove : S.frogLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Opacity(
            opacity: active ? 1 : 0.25,
            child: const Text('🐸', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

/// Переключатель «⭐ задача недели» — так задача попадает на экран «Неделя».
class StarToggle extends StatelessWidget {
  const StarToggle({required this.active, required this.onTap, super.key});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: active ? S.weekUnmark : S.weekMark,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            active ? Icons.star : Icons.star_border,
            size: 18,
            color: active ? scheme.tertiary : scheme.outline,
          ),
        ),
      ),
    );
  }
}

/// Теплокарта активности по дням (стиль календаря коммитов):
/// колонка — неделя, строка — день недели.
class HeatmapCalendar extends StatelessWidget {
  const HeatmapCalendar({required this.days, super.key});

  final List<DayLog> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (days.isEmpty) return const SizedBox.shrink();
    final maxCount = days.fold(1, (max, d) => d.count > max ? d.count : max);
    // Выравниваем начало на понедельник.
    final lead = days.first.date.weekday - 1;
    final cells = <DayLog?>[...List<DayLog?>.filled(lead, null), ...days];
    final weeks = (cells.length / 7).ceil();
    return SizedBox(
      height: 7 * 14 + 6,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: weeks,
        itemBuilder: (context, w) {
          return Column(
            children: [
              for (var d = 0; d < 7; d++)
                Builder(
                  builder: (context) {
                    final index = w * 7 + d;
                    final day = index < cells.length ? cells[index] : null;
                    final intensity = day == null ? 0.0 : day.count / maxCount;
                    return Tooltip(
                      message: day == null
                          ? ''
                          : '${day.date.day}.${day.date.month.toString().padLeft(2, '0')} — ${day.count} 🍅',
                      child: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: day == null || day.count == 0
                              ? scheme.surfaceContainerHighest
                              : scheme.primary.withValues(
                                  alpha: 0.25 + 0.75 * intensity,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Имя корзины планировщика.
String plannerTabLabel(PlannerTab tab) => switch (tab) {
  PlannerTab.inbox => S.inbox,
  PlannerTab.tomorrow => S.tomorrow,
  PlannerTab.week => S.week,
  PlannerTab.later => S.later,
};

/// Снекбар «Задача удалена» с отменой.
void showUndoSnack(BuildContext context, {required VoidCallback onUndo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(S.taskDeleted),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        width: 360,
        action: SnackBarAction(label: S.undo, onPressed: onUndo),
      ),
    );
}

/// Меню ⋮ задачи из «Сегодня»: помидоры, готово, разбить/слить, корзины.
class TaskMenu extends StatelessWidget {
  const TaskMenu({required this.task, super.key});

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
            // removeAt пишет в корзину синхронно (до реального disk I/O),
            // поэтому свежая запись уже здесь.
            final trash = cubit.state.trash;
            if (trash.isNotEmpty) {
              showUndoSnack(
                context,
                onUndo: () => cubit.restoreFromTrash(trash.first),
              );
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'plus', child: Text(S.menuAddPomo)),
        PopupMenuItem(
          value: 'minus',
          enabled: task.durationMinutes > 1,
          child: Text(S.menuRemovePomo),
        ),
        PopupMenuItem(value: 'done', child: Text(S.menuMarkDone)),
        PopupMenuItem(value: 'doneAll', child: Text(S.menuCloseWhole)),
        PopupMenuItem(value: 'split', child: Text(S.menuSplit)),
        PopupMenuItem(value: 'merge', child: Text(S.menuMerge)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'inbox', child: Text('↩ ${S.menuToInbox}')),
        PopupMenuItem(value: 'tomorrow', child: Text(S.menuToTomorrow)),
        PopupMenuItem(value: 'later', child: Text(S.menuToLater)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text(S.delete)),
      ],
    );
  }
}

/// Новая категория из диалога сразу попадает в настройки —
/// появляется во всех дропдаунах, схема таймера — по умолчанию.
void registerCategory(SettingsCubit settings, String category) {
  final name = category.trim().replaceAll(' ', '-');
  final current = settings.state.settings;
  if (name.isEmpty || current.categories.containsKey(name)) return;
  settings.update(
    current.copyWith(categories: {...current.categories, name: null}),
  );
}

/// Диалог редактирования задачи/записи: категория — выбор из списка ИЛИ
/// свободный ввод новой (она сразу регистрируется в настройках).
/// [minutes] != null — добавляется поле минут (записи «Сделано»).
Future<({String category, String description, int? minutes})?>
showTaskEditDialog(
  BuildContext context, {
  required String title,
  required String category,
  required String description,
  int? minutes,
}) {
  // Кубит — до showDialog: builder ленив, исходный context может умереть.
  final settingsCubit = context.read<SettingsCubit>();
  final categories = settingsCubit.state.settings.categories.keys.toList();
  final catController = TextEditingController(text: category);
  final descController = TextEditingController(text: description);
  final minController = minutes == null
      ? null
      : TextEditingController(text: '$minutes');
  return showDialog<({String category, String description, int? minutes})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownMenu<String>(
              controller: catController,
              initialSelection: categories.contains(category)
                  ? category
                  : null,
              // Клик в поле — курсор: можно вписать новую категорию.
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: Text(S.categoryHint),
              dropdownMenuEntries: [
                for (final c in categories)
                  DropdownMenuEntry(value: c, label: c),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: S.descriptionHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (minController != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: minController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: S.minutesField,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(S.close),
        ),
        FilledButton(
          onPressed: () {
            final cat = catController.text.trim();
            registerCategory(settingsCubit, cat);
            Navigator.of(dialogContext).pop((
              category: cat,
              description: descController.text.trim(),
              minutes: minController == null
                  ? null
                  : int.tryParse(minController.text.trim()),
            ));
          },
          child: Text(S.save),
        ),
      ],
    ),
  ).whenComplete(() {
    catController.dispose();
    descController.dispose();
    minController?.dispose();
  });
}

/// Общий вид ошибки с кнопкой повтора.
class ErrorPane extends StatelessWidget {
  const ErrorPane({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${S.errorPrefix}$message', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(S.retry)),
        ],
      ),
    );
  }
}
