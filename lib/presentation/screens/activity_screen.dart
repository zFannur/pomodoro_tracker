import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart' show dateHuman;
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
                                  onTap: () => cubit.toggleDistracting(row.key),
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
  static String _name(ActivityRow row) {
    final browser = browserNames[row.app];
    if (browser == null) {
      return row.app.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
    }
    return row.title.isEmpty ? browser : '$browser: ${row.title}';
  }
}

/// «1 ч 05 мин», «12 мин», «<1 мин».
String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes == 0) return '<1 ${S.minShort}';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m ${S.minShort}';
  return '$h ${S.hourShort} ${m.toString().padLeft(2, '0')} ${S.minShort}';
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.name,
    required this.seconds,
    required this.maxSeconds,
    required this.distracting,
    this.onTap,
  });

  final IconData icon;
  final String name;
  final int seconds;
  final int maxSeconds;
  final bool distracting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = distracting ? scheme.error : scheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
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
          ],
        ),
      ),
    );
  }
}
