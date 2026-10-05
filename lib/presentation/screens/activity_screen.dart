import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart' show dateHuman, two;
import '../../services/activity_tracker.dart' show browserNames;
import '../cubits/activity_cubit.dart';

/// Сколько строк показываем, остальное сворачиваем в «прочее».
const _topRows = 50;

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!Platform.isWindows) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            S.activityWindowsOnly,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return BlocBuilder<ActivityCubit, ActivityState>(
      builder: (context, state) {
        final cubit = context.read<ActivityCubit>();
        final top = state.rows.take(_topRows).toList();
        final restSeconds = state.rows
            .skip(_topRows)
            .fold(0, (sum, r) => sum + r.seconds);
        final maxSeconds = top.isEmpty ? 1 : top.first.seconds;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: cubit.prevDay,
                      ),
                      Text(
                        dateHuman(state.date),
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: state.isToday ? null : cubit.nextDay,
                      ),
                    ],
                  ),
                  if (state.rows.isNotEmpty) ...[
                    Text(
                      _summary(state),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      S.activityHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.isSelectionMode) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          S.activitySelected(state.selected.length),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _confirmAndDelete(
                            context,
                            date: state.date,
                            count: state.selected.length,
                            everywhere: false,
                            onConfirm: () => cubit.deleteSelected(everywhere: false),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(S.activityDeleteDay),
                        ),
                        OutlinedButton(
                          onPressed: () => _confirmAndDelete(
                            context,
                            date: state.date,
                            count: state.selected.length,
                            everywhere: true,
                            onConfirm: () => cubit.deleteSelected(everywhere: true),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(S.activityDeleteAllDays),
                        ),
                        TextButton(
                          onPressed: cubit.clearSelection,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(S.cancel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: state.rows.isEmpty
                        ? Center(
                            child: Text(
                              S.activityEmpty,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final row in top)
                                _ActivityTile(
                                  icon: browserNames.containsKey(row.app)
                                      ? Icons.language
                                      : Icons.desktop_windows_outlined,
                                  name: _name(row),
                                  seconds: row.seconds,
                                  maxSeconds: maxSeconds,
                                  distracting: state.isDistracting(row),
                                  selectionMode: state.isSelectionMode,
                                  selected: state.isSelected(row),
                                  onTap: state.isSelectionMode
                                      ? () => cubit.toggleSelected(row)
                                      : () => cubit.toggleDistracting(row.key),
                                  onLongPress: () => cubit.toggleSelected(row),
                                  onToggleSelected: () =>
                                      cubit.toggleSelected(row),
                                  onMenuSelected: (action) {
                                    if (action == 'select') {
                                      if (!state.isSelected(row)) {
                                        cubit.toggleSelected(row);
                                      }
                                    } else if (action == 'deleteDay') {
                                      _confirmAndDelete(
                                        context,
                                        date: state.date,
                                        count: 1,
                                        everywhere: false,
                                        onConfirm: () => cubit.deleteRow(
                                          row,
                                          everywhere: false,
                                        ),
                                      );
                                    } else if (action == 'deleteAll') {
                                      _confirmAndDelete(
                                        context,
                                        date: state.date,
                                        count: 1,
                                        everywhere: true,
                                        onConfirm: () => cubit.deleteRow(
                                          row,
                                          everywhere: true,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              if (restSeconds > 0)
                                _ActivityTile(
                                  icon: Icons.more_horiz,
                                  name: S.activityOther,
                                  seconds: restSeconds,
                                  maxSeconds: maxSeconds,
                                  distracting: false,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// «Всего 2 ч 05 мин · отвлечения 30% · в помидорах фокус 80%».
  static String _summary(ActivityState state) {
    final focus = state.focusPercent;
    return [
      S.activityTotal(_duration(state.totalSeconds)),
      S.activityDistractions(state.distractingPercent),
      if (focus != null) S.activityPomoFocus(focus),
    ].join(' · ');
  }

  /// Имя exe без `.exe`; у браузера — «Chrome: название вкладки».
  static String _name(ActivityRow row) =>
      formatActivityName(row.app, row.title);
}

/// Подтверждение удаления записей через диалог.
Future<void> _confirmAndDelete(
  BuildContext context, {
  required DateTime date,
  required int count,
  required bool everywhere,
  required Future<void> Function() onConfirm,
}) async {
  final dateStr = '${two(date.day)}.${two(date.month)}';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        everywhere
            ? S.activityDeleteConfirmAll(count)
            : S.activityDeleteConfirmDay(count, dateStr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(S.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            S.delete,
            style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await onConfirm();
  }
}

/// Имя exe без `.exe`; у браузера — «Chrome: название вкладки».
String formatActivityName(String app, String title) {
  final browser = browserNames[app.toLowerCase()];
  if (browser == null) {
    return app.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
  }
  return title.isEmpty ? browser : '$browser: $title';
}

/// «1 ч 05 мин», «12 мин», «<1 мин».
String formatActivityDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes == 0) return '<1 ${S.minShort}';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m ${S.minShort}';
  return '$h ${S.hourShort} ${m.toString().padLeft(2, '0')} ${S.minShort}';
}

String _duration(int seconds) => formatActivityDuration(seconds);

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.name,
    required this.seconds,
    required this.maxSeconds,
    required this.distracting,
    this.selectionMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onToggleSelected,
    this.onMenuSelected,
  });

  final IconData icon;
  final String name;
  final int seconds;
  final int maxSeconds;
  final bool distracting;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelected;
  final PopupMenuItemSelected<String>? onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = distracting ? scheme.error : scheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: onToggleSelected != null
                    ? (_) => onToggleSelected!()
                    : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
            ],
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: distracting ? scheme.error : null),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: seconds / maxSeconds,
                  minHeight: 14,
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Text(
                _duration(seconds),
                textAlign: TextAlign.right,
                style: TextStyle(color: distracting ? scheme.error : null),
              ),
            ),
            if (onMenuSelected != null) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: onMenuSelected,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'select',
                    child: Text(S.activitySelect),
                  ),
                  PopupMenuItem(
                    value: 'deleteDay',
                    child: Text(S.activityDeleteDay),
                  ),
                  PopupMenuItem(
                    value: 'deleteAll',
                    child: Text(S.activityDeleteAllDays),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
