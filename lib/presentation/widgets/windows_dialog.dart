import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/insights.dart';
import '../../services/activity_tracker.dart' show formatActivityName;
import '../cubits/activity_cubit.dart';
import '../cubits/insight_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../screens/activity_screen.dart' show formatActivityDuration;
import '../screens/help_screen.dart';

/// Сколько строк видно сразу, остальные раскрывает «Ещё N».
const _shownRows = 12;

/// Ширина диалога: AlertDialog + его поля (24·2) + отступы от края (40·2).
const _dialogWidth = 520.0;
const _fullscreenBelow = _dialogWidth + 48 + 80;

/// Есть ли смысл показывать пункты «Окна…»: трекер ведётся только на Windows,
/// и нужен [ActivityCubit] в дереве. [isWindows] — подмена платформы в тестах.
bool hasWindowsTracker(BuildContext context, {bool? isWindows}) {
  if (!(isWindows ?? Platform.isWindows)) return false;
  return _maybeRead<ActivityCubit>(context) != null;
}

T? _maybeRead<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// «6 помидоров · 2 ч 30 мин · трекер видел 2 ч 21 мин».
String windowsSubtitle(List<PomoSession> sessions, List<ActivityRow> rows) {
  final minutes = sessions.fold(0, (sum, s) => sum + s.minutes);
  final seen = rows.fold(0, (sum, r) => sum + r.seconds);
  return S.windowsSubtitle(
    sessions.length,
    formatActivityDuration(minutes * 60),
    formatActivityDuration(seen),
  );
}

/// Окна, открытые во время помидоров задачи, — один помидор или все.
///
/// [rows] — функция, а не список: после смены флажка «отвлекающее» диалог
/// перестраивается и спрашивает строки заново. [breakdown] (необязательно) —
/// раскладка по помидорам: подпись и окна каждого. [note] — серая строка
/// под пустым состоянием (по умолчанию — про Windows и 60 дней).
Future<void> showWindowsDialog(
  BuildContext context, {
  required String title,
  String subtitle = '',
  required List<ActivityRow> Function() rows,
  List<({String label, List<ActivityRow> rows})> Function()? breakdown,
  String empty = '',
  String note = '',
}) {
  // Кубит — до showDialog: маршрут диалога не видит провайдеров экрана.
  final cubit = context.read<ActivityCubit>();
  final narrow = MediaQuery.sizeOf(context).width < _fullscreenBelow;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final body = _WindowsBody(
        cubit: cubit,
        subtitle: subtitle,
        rows: rows,
        breakdown: breakdown,
        empty: empty,
        note: note,
      );
      if (narrow) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                tooltip: S.close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              actions: const [HelpButton(section: 'windows')],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: body,
            ),
          ),
        );
      }
      return AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(title)),
            const HelpButton(section: 'windows'),
          ],
        ),
        content: SizedBox(
          width: _dialogWidth,
          child: SingleChildScrollView(child: body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.close),
          ),
        ],
      );
    },
  );
}

/// «Окна задачи»: окна всех помидоров задачи. Сессии берутся из журнала
/// [InsightCubit] (если его нет в дереве — пустое состояние).
Future<void> showTaskWindowsDialog(
  BuildContext context, {
  required String taskId,
  required String description,
  required String category,
}) {
  final activity = context.read<ActivityCubit>();
  final days = _maybeRead<InsightCubit>(context)?.state.days ?? const [];
  final fmt = _maybeRead<SettingsCubit>(context)?.state.settings.timeFmt ??
      TimeFmt.h24;
  final sessions = sessionsOfTask(
    days,
    taskId: taskId,
    description: description,
    category: category,
  );
  return showWindowsDialog(
    context,
    title: description.isEmpty ? '—' : description,
    subtitle: sessions.isEmpty
        ? ''
        : windowsSubtitle(sessions, activity.segmentsForAll(sessions)),
    rows: () => activity.segmentsForAll(sessions),
    breakdown: sessions.length < 2
        ? null
        : () => [
            for (final s in sessions.reversed)
              (
                label: S.windowsSessionLabel(
                  s.start,
                  s.minutes,
                  formatClock(s.start, fmt),
                ),
                rows: activity.segmentsFor(s),
              ),
          ],
    empty: sessions.isEmpty ? S.windowsNoPomos : S.windowsEmptyTask,
  );
}

class _WindowsBody extends StatefulWidget {
  const _WindowsBody({
    required this.cubit,
    required this.subtitle,
    required this.rows,
    required this.breakdown,
    required this.empty,
    required this.note,
  });

  final ActivityCubit cubit;
  final String subtitle;
  final List<ActivityRow> Function() rows;
  final List<({String label, List<ActivityRow> rows})> Function()? breakdown;
  final String empty;
  final String note;

  @override
  State<_WindowsBody> createState() => _WindowsBodyState();
}

class _WindowsBodyState extends State<_WindowsBody> {
  var _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return BlocBuilder<ActivityCubit, ActivityState>(
      bloc: widget.cubit,
      builder: (context, state) {
        final rows = widget.rows();
        final parts = widget.breakdown?.call() ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle.isNotEmpty) Text(widget.subtitle, style: muted),
            if (rows.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.empty.isEmpty ? S.sessionActivityEmpty : widget.empty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.note.isEmpty ? S.windowsTrackerNote : widget.note,
                style: muted,
              ),
            ] else ...[
              const SizedBox(height: 10),
              _FocusBar(rows: rows, state: state),
              const SizedBox(height: 10),
              for (final row in _showAll ? rows : rows.take(_shownRows))
                _WindowRow(
                  row: row,
                  maxSeconds: rows.first.seconds,
                  distracting: state.isDistracting(row),
                  onFlag: () => widget.cubit.toggleDistracting(row.key),
                ),
              if (!_showAll && rows.length > _shownRows)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = true),
                    child: Text(S.windowsMore(rows.length - _shownRows)),
                  ),
                ),
              if (parts.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    S.windowsBySession,
                    style: theme.textTheme.titleSmall,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final part in parts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(_partLine(part), style: muted),
                      ),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }

  /// «Вт 10:15 · 25 мин — Code 18 мин, Chrome: docs 5 мин, Telegram 2 мин».
  static String _partLine(({String label, List<ActivityRow> rows}) part) {
    if (part.rows.isEmpty) return part.label;
    final top = part.rows
        .take(3)
        .map(
          (r) =>
              '${formatActivityName(r.app, r.title)} '
              '${formatActivityDuration(r.seconds)}',
        )
        .join(', ');
    return '${part.label} — $top';
  }
}

/// Полоса «работа / отвлечения» по секундам строк.
class _FocusBar extends StatelessWidget {
  const _FocusBar({required this.rows, required this.state});

  final List<ActivityRow> rows;
  final ActivityState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = rows.fold(0, (sum, r) => sum + r.seconds);
    if (total == 0) return const SizedBox.shrink();
    final bad = rows
        .where(state.isDistracting)
        .fold(0, (sum, r) => sum + r.seconds);
    final badPercent = (100 * bad / total).round();
    final workPercent = 100 - badPercent;
    final small = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (workPercent > 0)
                  Expanded(
                    flex: workPercent,
                    child: ColoredBox(color: scheme.primary),
                  ),
                if (badPercent > 0)
                  Expanded(
                    flex: badPercent,
                    child: ColoredBox(color: scheme.error),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(S.windowsWork(workPercent), style: small),
            Text(
              S.windowsDistractions(badPercent),
              style: small?.copyWith(color: scheme.error),
            ),
          ],
        ),
      ],
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({
    required this.row,
    required this.maxSeconds,
    required this.distracting,
    required this.onFlag,
  });

  final ActivityRow row;
  final int maxSeconds;
  final bool distracting;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = distracting ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatActivityName(row.app, row.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: distracting ? scheme.error : null),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: maxSeconds == 0 ? 0 : row.seconds / maxSeconds,
                    minHeight: 4,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              formatActivityDuration(row.seconds),
              textAlign: TextAlign.right,
              style: TextStyle(color: distracting ? scheme.error : null),
            ),
          ),
          IconButton(
            tooltip: S.windowsFlagTip,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              distracting ? Icons.flag : Icons.flag_outlined,
              size: 20,
              color: distracting ? scheme.error : scheme.onSurfaceVariant,
            ),
            onPressed: onFlag,
          ),
        ],
      ),
    );
  }
}
