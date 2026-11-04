import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart' show dateKey;
import '../../domain/entities/episode.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../cubits/insight_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';
import 'common.dart';
import 'episode_sheet.dart';

/// Эпизод «вчера», о котором стоит спросить утром: не сдвинувшаяся 🐸 или
/// как минимум два переноса. 🐸 важнее — перенос без неё не упоминаем.
Episode? _yesterdayEpisode(DayLog yesterday) {
  Episode? latest(Iterable<Episode> list) => list.fold<Episode?>(
    null,
    (best, e) => best == null || e.at.isAfter(best.at) ? e : best,
  );
  final frog = latest(
    yesterday.episodes.where((e) => e.source == EpisodeSource.frog),
  );
  if (frog != null) return frog;
  final defers = yesterday.episodes
      .where((e) => e.source == EpisodeSource.defer)
      .toList();
  return defers.length >= 2 ? latest(defers) : null;
}

/// Карточка дня над «СЕЙЧАС»: самочувствие, «вчера», план «если — то».
/// Показывается только то, что нужно сейчас; пусто — карточки нет вовсе.
///
/// Время читается при перестройке, а не по таймеру: граница 17:00 подхватится
/// при ближайшем изменении состояния (на таймере оно идёт каждую секунду).
class DayCard extends StatelessWidget {
  const DayCard({super.key});

  Future<void> _editFrog(BuildContext context, PomoTask frog) async {
    final tasks = context.read<TasksCubit>();
    final r = await showTaskEditDialog(
      context,
      title: S.editTask,
      category: frog.category,
      description: frog.description,
      firstStep: frog.firstStep,
      cue: frog.cue,
      cueAt: frog.cueAt,
      planExpanded: true,
    );
    if (r == null) return;
    // Индекс — в момент сохранения: список мог сдвинуться, пока был открыт диалог.
    final index = tasks.todoIndexOf(frog);
    if (index < 0) return;
    await tasks.edit(
      index,
      category: r.category.isEmpty ? null : r.category,
      description: r.description.isEmpty ? null : r.description,
      firstStep: r.firstStep,
      cue: r.cue,
      cueAt: r.cueAt,
    );
  }

  void _askWhy(BuildContext context, Episode episode) {
    final tasks = context.read<TasksCubit>().state;
    PomoTask? task;
    if (episode.taskId.isNotEmpty) {
      for (final t in [...tasks.todo, ...tasks.planner]) {
        if (t.id == episode.taskId) task = t;
      }
    }
    showEpisodeSheet(
      context,
      source: episode.source ?? EpisodeSource.manual,
      task: task,
      existing: episode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state.settings;
    final insight = context.watch<InsightCubit>();
    final tasks = context.watch<TasksCubit>().state;
    // Пока данные не загружены, отметок «нет» ещё не значит «не отмечено».
    if (!settings.dayCard || insight.state.status != InsightStatus.ready) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final now = clock.now();
    final today = dateKey(logicalDate(now));
    final hiddenToday = settings.dayCardHidden == today;
    final ck = insight.checkIn;
    // Ночь до 05:00 — ещё вечер вчерашнего логического дня.
    final evening = now.hour >= 17 || now.hour < dayStartHour;
    final morning = !evening && (ck.sleep == null || ck.energy == null);
    final mood = evening && ck.mood == null;
    final episode = hiddenToday ? null : _yesterdayEpisode(insight.yesterday);
    final frog = tasks.todo.where((t) => t.frog).firstOrNull;
    final planTask = frog ?? tasks.current;
    final plan = hiddenToday || planTask == null || planTask.cue.trim().isEmpty
        ? null
        : planTask;
    if (!morning && !mood && episode == null && plan == null) {
      return const SizedBox.shrink();
    }
    final defers = episode == null
        ? 0
        : insight.yesterday.episodes
              .where((e) => e.source == EpisodeSource.defer)
              .length;

    // Wrap, а не Row: на телефоне подпись и пять точек в одну строку не влезают.
    Widget rated(String label, int? value, ValueChanged<int> onChanged) => Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        _Dots(value: value, onChanged: onChanged, semanticLabel: label),
      ],
    );

    final children = <Widget>[
      if (morning)
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            rated(
              S.sleepLabel,
              ck.sleep,
              (v) => insight.setCheckIn(CheckIn(sleep: v)),
            ),
            rated(
              S.energyLabel,
              ck.energy,
              (v) => insight.setCheckIn(CheckIn(energy: v)),
            ),
          ],
        ),
      if (mood)
        rated(
          S.moodQuestion,
          null,
          (v) => insight.setCheckIn(CheckIn(mood: v)),
        ),
      if (episode != null) ...[
        if (morning || mood) const SizedBox(height: 8),
        Text(
          episode.source == EpisodeSource.frog
              ? S.yesterdayFrog
              : S.yesterdayDefers(defers),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _askWhy(context, episode),
              child: Text(S.whatGotInTheWay),
            ),
            if (frog != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _editFrog(context, frog),
                child: Text(S.firstStepForFrog),
              ),
          ],
        ),
      ],
      if (plan != null) ...[
        if (morning || mood || episode != null) const SizedBox(height: 8),
        Text(
          S.planLine(
            plan.cue.trim(),
            plan.firstStep.trim().isNotEmpty
                ? plan.firstStep.trim()
                : plan.description,
            plan.cueAt,
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
              // Крестик скрывает только «Вчера» и «План»: самочувствие
              // исчезает само, когда отмечено.
              if (episode != null || plan != null)
                IconButton(
                  tooltip: S.close,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => context.read<SettingsCubit>().update(
                    settings.copyWith(dayCardHidden: today),
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пять кружков 1–5: выбранный и все до него закрашены. Область нажатия —
/// 32 px, чтобы попадать пальцем.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final int? value;
  final ValueChanged<int> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: S.dotsLabel(semanticLabel, value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Semantics(
              button: true,
              label: '$i',
              child: InkWell(
                key: ValueKey('dots:$semanticLabel:$i'),
                customBorder: const CircleBorder(),
                onTap: () => onChanged(i),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value != null && i <= value!
                            ? scheme.primary
                            : null,
                        border: Border.all(
                          color: value != null && i <= value!
                              ? scheme.primary
                              : scheme.outline,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
