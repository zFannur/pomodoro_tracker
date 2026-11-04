import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart' show sprintId, two;
import '../../domain/entities/episode.dart';
import '../../domain/entities/experiment.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/insights.dart';
import '../../domain/strategies.dart';
import '../cubits/insight_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../home_shell.dart';
import '../widgets/common.dart';
import '../widgets/episode_sheet.dart';
import '../widgets/ips_dialog.dart';
import 'activity_screen.dart';

/// Значение метрики для показа: «+25 мин» / «10:40» / «8 мин» / «12%» / «3».
/// [lag] — «первый помидор» считается от начала окна, а не от часа суток.
String formatInsightValue(
  InsightMetric m,
  double? v, {
  required bool lag,
}) {
  if (v == null) return '—';
  switch (m) {
    case InsightMetric.firstStart:
      if (lag) return S.lagValue(v.round());
      // Без расписания это средний час старта, отсчитанный от начала суток.
      final total = (v + dayStartHour * 60).round() % (24 * 60);
      return '${two(total ~/ 60)}:${two(total % 60)}';
    case InsightMetric.idle:
      return S.minutesValue(v.round());
    case InsightMetric.deferrals:
      return '${v.round()}';
    case InsightMetric.frogFirst:
    case InsightMetric.distract:
    case InsightMetric.success:
      return '${v.round()}%';
  }
}

/// «Разбор»: недельная картина, эпизоды и (на Windows) окна.
class InsightScreen extends StatelessWidget {
  const InsightScreen({super.key, this.showWindows, this.aiSlot});

  /// null — по платформе (трекер окон есть только на Windows).
  final bool? showWindows;

  /// Место под кнопку и карточку ИИ-разбора (P11).
  final Widget? aiSlot;

  @override
  Widget build(BuildContext context) {
    final windows = showWindows ?? Platform.isWindows;
    return DefaultTabController(
      key: ValueKey(windows),
      length: windows ? 3 : 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: S.insightTabWeek),
              Tab(text: S.insightTabEpisodes),
              if (windows) Tab(text: S.insightTabWindows),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _WeekTab(showWindows: windows, aiSlot: aiSlot),
                const _EpisodesTab(),
                if (windows) const ActivityScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Неделя
// ---------------------------------------------------------------------------

class _WeekTab extends StatefulWidget {
  const _WeekTab({required this.showWindows, this.aiSlot});

  final bool showWindows;
  final Widget? aiSlot;

  @override
  State<_WeekTab> createState() => _WeekTabState();
}

class _WeekTabState extends State<_WeekTab> {
  /// «Не сейчас»: предложение скрыто до следующего открытия вкладки «Разбор».
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    homeTab.addListener(_onHomeTab);
  }

  @override
  void dispose() {
    homeTab.removeListener(_onHomeTab);
    super.dispose();
  }

  void _onHomeTab() {
    if (_dismissed && homeTab.value == kInsightTab) {
      setState(() => _dismissed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insight = context.watch<InsightCubit>();
    final settings = context.watch<SettingsCubit>().state.settings;
    final state = insight.state;
    switch (state.status) {
      case InsightStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case InsightStatus.failure:
        return ErrorPane(message: state.error, onRetry: insight.refresh);
      case InsightStatus.ready:
        break;
    }
    final theme = Theme.of(context);
    final today = logicalDate(clock.now());
    final week = sprintId(today).split('-').last;
    final observation = insight.observation;
    final windows = parseSessionWindows(settings.sessionWindows);
    final review = state.sprint?.review;
    final Widget? ai = widget.aiSlot ?? (review == null ? null : _ReviewCard(review));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text.rich(
              TextSpan(
                text: S.insightWeekTitle(week),
                children: [
                  if (observation)
                    TextSpan(
                      text: ' ${S.insightObservationSuffix}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _Tiles(insight: insight, showWindows: widget.showWindows),
            const SizedBox(height: 12),
            _CausesCard(insight: insight),
            const SizedBox(height: 12),
            _WellbeingCard(insight: insight, windows: windows, today: today),
            const SizedBox(height: 12),
            _ExperimentSection(
              insight: insight,
              today: today,
              showWindows: widget.showWindows,
              dismissed: _dismissed,
              onDismiss: () => setState(() => _dismissed = true),
            ),
            if (ai != null) ...[const SizedBox(height: 12), ai],
            _IpsSection(days: state.days, today: today),
          ],
        ),
      ),
    );
  }
}

/// Плитки недели. Δ — к прошлой неделе, «база» — к неделе наблюдения.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.insight, required this.showWindows});

  final InsightCubit insight;
  final bool showWindows;

  static String _value(InsightMetric m, WeekInsight w) {
    final v = metricValue(w, m);
    if (v == null) return '—';
    // «4/6»: дни с 🐸 первой из активных дней.
    if (m == InsightMetric.frogFirst) {
      return '${(v * w.activeDays / 100).round()}/${w.activeDays}';
    }
    return formatInsightValue(m, v, lag: w.firstStartIsLag);
  }

  /// Для «Переносов» ноль — тоже значение, поэтому у пустой недели данных нет.
  static bool _hasData(InsightMetric m, WeekInsight w) =>
      m != InsightMetric.deferrals || w.activeDays > 0 || w.episodes > 0;

  Widget _footer(
    BuildContext context,
    InsightMetric m,
    WeekInsight cur,
    WeekInsight prev,
    WeekInsight? base,
  ) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final now = metricValue(cur, m);
    if (now == null) return Text(S.insightNoData, style: small);
    final before = _hasData(m, prev) ? metricValue(prev, m) : null;
    final parts = <Widget>[];
    if (before != null) {
      final delta = now - before;
      final rounded = delta.abs().round();
      if (rounded == 0) {
        parts.add(Text('=', style: small));
      } else {
        final better = lowerIsBetter(m) ? delta < 0 : delta > 0;
        final unit =
            (m == InsightMetric.frogFirst ||
                m == InsightMetric.distract ||
                m == InsightMetric.success)
            ? '%'
            : '';
        parts.add(
          Text(
            '${delta > 0 ? '▲' : '▼'} $rounded$unit',
            style: small?.copyWith(
              color: better
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        );
      }
    }
    if (base != null && metricValue(base, m) != null) {
      parts.add(Text(S.insightBase(_value(m, base)), style: small));
    }
    return Wrap(spacing: 6, children: parts);
  }

  @override
  Widget build(BuildContext context) {
    final cur = insight.current;
    final prev = insight.previousWeek;
    final base = insight.observation ? null : insight.baselineInsight;
    final metrics = [
      InsightMetric.firstStart,
      InsightMetric.idle,
      InsightMetric.frogFirst,
      InsightMetric.deferrals,
      if (showWindows) InsightMetric.distract,
    ];
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return StatGrid(
      perRow: narrow ? 2 : metrics.length,
      tiles: [
        for (final m in metrics)
          StatTile(
            label: S.metric(m),
            value: _value(m, cur),
            footer: _footer(context, m, cur, prev, base),
          ),
      ],
    );
  }
}

class _CausesCard extends StatelessWidget {
  const _CausesCard({required this.insight});

  final InsightCubit insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final causes = insight.current.causes;
    final stats = insight.stats;
    final entries = [
      for (final e in causes.entries)
        if (e.key != Cause.external) e,
    ]..sort((a, b) => b.value.compareTo(a.value));
    final external = causes[Cause.external] ?? 0;
    final maxCount = entries.isEmpty ? 1 : entries.first.value;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    String? best(Cause c) {
      for (final k in insight.ranked(c)) {
        final s = stats[k];
        if (s != null && s.tries > 0) {
          return S.causeBest(S.strategyTitle(k), s.wins, s.tries);
        }
      }
      return null;
    }

    return SectionCard(
      title: S.insightCauses,
      child: causes.isEmpty
          ? Text(S.causesEmpty, style: muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.cause(e.key), style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value / maxCount,
                                  minHeight: 10,
                                  color: theme.colorScheme.primary,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${e.value}',
                              style: theme.textTheme.labelLarge,
                            ),
                          ],
                        ),
                        if (best(e.key) case final text?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(text, style: muted),
                          ),
                      ],
                    ),
                  ),
                // «Отвлекли» — не избегание: отдельной серой строкой.
                if (external > 0) Text(S.causeExternal(external), style: muted),
              ],
            ),
    );
  }
}

class _WellbeingCard extends StatelessWidget {
  const _WellbeingCard({
    required this.insight,
    required this.windows,
    required this.today,
  });

  final InsightCubit insight;
  final List<SessionWindow> windows;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = DateTime(today.year, today.month, today.day - 27);
    final days = [
      for (final d in insight.state.days)
        if (!d.date.isBefore(from) && !d.date.isAfter(today)) d,
    ];
    final lines = <String>[];
    for (final field in CheckInField.values) {
      for (final m in [InsightMetric.idle, InsightMetric.frogFirst]) {
        final split = checkInSplit(days, field, m, windows: windows);
        if (split == null || split.good == null || split.bad == null) continue;
        lines.add(
          S.wellbeingLine(
            field == CheckInField.sleep ? S.sleepLabel : S.energyLabel,
            S.metric(m),
            formatInsightValue(m, split.good, lag: false),
            formatInsightValue(m, split.bad, lag: false),
          ),
        );
      }
    }
    return SectionCard(
      title: S.wellbeingTitle,
      child: lines.isEmpty
          ? Text(
              S.wellbeingHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
    );
  }
}

class _ExperimentSection extends StatelessWidget {
  const _ExperimentSection({
    required this.insight,
    required this.today,
    required this.showWindows,
    required this.dismissed,
    required this.onDismiss,
  });

  final InsightCubit insight;
  final DateTime today;
  final bool showWindows;
  final bool dismissed;
  final VoidCallback onDismiss;

  Experiment? _suggest() {
    for (final week in [insight.previousWeek, insight.baselineInsight]) {
      if (week == null) continue;
      final e = suggestExperiment(
        week,
        insight.stats,
        hasTracker: showWindows,
      );
      if (e != null) return e;
    }
    return null;
  }

  Widget _verdict(BuildContext context, String prevId, Experiment exp) {
    final theme = Theme.of(context);
    final week = insight.previousWeek;
    final now = metricValue(week, exp.metric);
    final lag = week.firstStartIsLag;
    final auto = verdictFor(
      metric: exp.metric,
      baseline: exp.baseline,
      now: now,
      days: week.activeDays,
    );
    // Сохранённый вердикт важнее расчётного: пользователь мог его поправить.
    final shown = exp.verdict ?? auto;
    return SectionCard(
      title: S.experimentTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.experimentResult(exp.hypothesis),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.experimentWasNow(
              S.metric(exp.metric),
              formatInsightValue(exp.metric, exp.baseline, lag: lag),
              formatInsightValue(exp.metric, now, lag: lag),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<Verdict>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                for (final v in [Verdict.works, Verdict.same, Verdict.worse])
                  ButtonSegment(value: v, label: Text(S.verdictButton(v))),
              ],
              selected: shown == Verdict.unclear ? {} : {shown},
              onSelectionChanged: (selection) {
                // Повторный тап по предвыбранному пустит пустой набор:
                // это подтверждение расчётного вердикта.
                final v = selection.isEmpty ? shown : selection.first;
                if (v == Verdict.unclear) return;
                insight.setVerdict(prevId, v);
              },
            ),
          ),
          if (shown == Verdict.unclear)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                S.insightNoData,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _current(BuildContext context, Experiment exp) {
    final theme = Theme.of(context);
    final cur = insight.current;
    final end = insight.state.sprint?.end ?? today;
    // UTC, чтобы переход на летнее время не съедал день.
    final left = DateTime.utc(end.year, end.month, end.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    return SectionCard(
      title: S.experimentTitle,
      trailing: TextButton(
        onPressed: insight.clearExperiment,
        child: Text(S.experimentClear),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exp.hypothesis, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            S.experimentCurrent(
              S.metric(exp.metric),
              formatInsightValue(
                exp.metric,
                exp.baseline,
                lag: cur.firstStartIsLag,
              ),
              formatInsightValue(
                exp.metric,
                metricValue(cur, exp.metric),
                lag: cur.firstStartIsLag,
              ),
              left < 0 ? 0 : left + 1,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestion(BuildContext context, Experiment? suggestion) {
    final theme = Theme.of(context);
    return SectionCard(
      title: S.experimentSuggested,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (suggestion != null) ...[
            Text(suggestion.hypothesis, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              S.metric(suggestion.metric),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (suggestion != null)
                FilledButton(
                  onPressed: () => insight.startExperiment(suggestion),
                  child: Text(S.experimentTake),
                ),
              OutlinedButton(
                onPressed: () => _custom(context),
                child: Text(S.experimentCustom),
              ),
              TextButton(
                onPressed: onDismiss,
                child: Text(S.experimentLater),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _custom(BuildContext context) async {
    final base = insight.previousWeek;
    final result = await _customExperiment(
      context,
      hasTracker: showWindows,
      base: base,
    );
    if (result != null) await insight.startExperiment(result);
  }

  @override
  Widget build(BuildContext context) {
    final state = insight.state;
    final previous = state.previous;
    final prevExp = previous?.experiment;
    final current = insight.experiment;
    final cards = <Widget>[
      if (previous != null && prevExp != null)
        _verdict(context, previous.id, prevExp),
      if (current != null)
        _current(context, current)
      else if (insight.observation)
        Text(
          S.experimentAfterObservation,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      else if (!dismissed)
        _suggestion(context, _suggest()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          cards[i],
        ],
      ],
    );
  }
}

/// Диалог «Свой эксперимент»: гипотеза, способ и метрика из списков.
Future<Experiment?> _customExperiment(
  BuildContext context, {
  required bool hasTracker,
  required WeekInsight base,
}) {
  var strategy = StrategyKind.firstStep;
  var metric = metricFor(strategy, hasTracker: hasTracker);
  final hypothesis = TextEditingController(
    text: S.hypothesis(strategy, metric),
  );
  // Пока пользователь не правил текст сам, он следует за выбором списков.
  var edited = false;
  final metrics = [
    for (final m in InsightMetric.values)
      if (m != InsightMetric.distract || hasTracker) m,
  ];
  final result = showDialog<Experiment>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        void regenerate() {
          if (!edited) hypothesis.text = S.hypothesis(strategy, metric);
        }

        return AlertDialog(
          title: Text(S.experimentCustomTitle),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: hypothesis,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => setState(() => edited = true),
                    decoration: InputDecoration(
                      labelText: S.fieldHypothesis,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: S.fieldStrategy,
                      border: const OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<StrategyKind>(
                        key: const ValueKey('experiment-strategy'),
                        isExpanded: true,
                        isDense: true,
                        value: strategy,
                        items: [
                          for (final k in StrategyKind.values)
                            DropdownMenuItem(
                              value: k,
                              child: Text(
                                S.strategyTitle(k),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (k) {
                          if (k == null) return;
                          setState(() {
                            strategy = k;
                            metric = metricFor(k, hasTracker: hasTracker);
                            regenerate();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: S.fieldMetric,
                      border: const OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<InsightMetric>(
                        key: const ValueKey('experiment-metric'),
                        isExpanded: true,
                        isDense: true,
                        value: metric,
                        items: [
                          for (final m in metrics)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                S.metric(m),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (m) {
                          if (m == null) return;
                          setState(() {
                            metric = m;
                            regenerate();
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(S.cancel),
            ),
            FilledButton(
              onPressed: hypothesis.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(
                      Experiment(
                        hypothesis: hypothesis.text.trim(),
                        strategy: strategy,
                        metric: metric,
                        baseline: metricValue(base, metric),
                      ),
                    ),
              child: Text(S.save),
            ),
          ],
        );
      },
    ),
  );
  result.whenComplete(hypothesis.dispose);
  return result;
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard(this.review);

  final WeekReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: S.reviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(review.summary, style: theme.textTheme.bodyMedium),
          for (final p in review.patterns)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${p.text}', style: theme.textTheme.bodyMedium),
                  if (p.evidence.isNotEmpty)
                    Text(
                      p.evidence,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IpsSection extends StatelessWidget {
  const _IpsSection({required this.days, required this.today});

  final List<DayLog> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = <({DateTime date, int score})>[
      for (final d in days)
        if (ipsScore(d.ips) case final score?) (date: d.date, score: score),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final doneThisMonth = days.any(
      (d) =>
          d.ips.isNotEmpty &&
          d.date.year == today.year &&
          d.date.month == today.month,
    );
    final due = !doneThisMonth && today.day <= 7;
    final history = results.length < 2
        ? null
        : results
              .skip(results.length > 6 ? results.length - 6 : 0)
              .map((r) => '${S.monthShort(r.date.month)} ${r.score}')
              .join(' · ');
    if (!due && history == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (due)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${S.ipsTitle} · ${S.ipsSubtitle}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => showIpsDialog(context),
                      child: Text(S.ipsTake),
                    ),
                  ],
                )
              else
                Text(S.ipsTitle, style: theme.textTheme.bodyMedium),
              if (history != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    history,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Эпизоды
// ---------------------------------------------------------------------------

class _EpisodesTab extends StatefulWidget {
  const _EpisodesTab();

  @override
  State<_EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends State<_EpisodesTab> {
  Cause? _filter;

  @override
  Widget build(BuildContext context) {
    final insight = context.watch<InsightCubit>();
    final state = insight.state;
    switch (state.status) {
      case InsightStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case InsightStatus.failure:
        return ErrorPane(message: state.error, onRetry: insight.refresh);
      case InsightStatus.ready:
        break;
    }
    final theme = Theme.of(context);
    final today = logicalDate(clock.now());
    final from = DateTime(today.year, today.month, today.day - 13);
    final groups = <({DayLog day, List<Episode> episodes})>[];
    for (final day in state.days) {
      if (day.date.isBefore(from) || day.date.isAfter(today)) continue;
      final list = [
        for (final e in day.episodes)
          if (_filter == null || e.cause == _filter) e,
      ]..sort((a, b) => a.at.compareTo(b.at));
      if (list.isNotEmpty) groups.add((day: day, episodes: list));
    }
    groups.sort((a, b) => b.day.date.compareTo(a.day.date));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in Cause.values)
                  FilterChip(
                    key: ValueKey('episode-filter:${c.name}'),
                    label: Text(S.cause(c)),
                    selected: _filter == c,
                    showCheckmark: false,
                    onSelected: (_) =>
                        setState(() => _filter = _filter == c ? null : c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  S.episodesEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  g.day.date == today
                      ? S.periodToday
                      : S.dayHeader(g.day.date),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              for (final e in g.episodes) _EpisodeRow(day: g.day, episode: e),
            ],
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.day, required this.episode});

  final DayLog day;
  final Episode episode;

  Widget _icon(ColorScheme scheme) {
    final color = scheme.onSurfaceVariant;
    return switch (episode.source) {
      EpisodeSource.idle => Icon(Icons.hourglass_empty, size: 18, color: color),
      EpisodeSource.stop => Icon(
        Icons.stop_circle_outlined,
        size: 18,
        color: color,
      ),
      EpisodeSource.defer => Icon(Icons.redo, size: 18, color: color),
      EpisodeSource.frog => const Text('🐸', style: TextStyle(fontSize: 16)),
      EpisodeSource.distract => Icon(Icons.open_in_new, size: 18, color: color),
      EpisodeSource.manual || null => Icon(
        Icons.psychology_alt_outlined,
        size: 18,
        color: color,
      ),
    };
  }

  void _openSheet(BuildContext context) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strategy = episode.strategy;
    final title = episode.source == EpisodeSource.distract && episode.app.isNotEmpty
        ? S.episodeDistract(episode.app)
        : (episode.task.isEmpty ? S.episodeNoTask : episode.task);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${two(episode.at.hour)}:${two(episode.at.minute)}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          SizedBox(width: 24, child: Center(child: _icon(scheme))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      key: ValueKey('episode-cause:${episode.id}'),
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        episode.cause == null
                            ? S.episodeNoCause
                            : S.cause(episode.cause!),
                      ),
                      onPressed: () => _openSheet(context),
                    ),
                    if (strategy != null)
                      Text(
                        S.strategyTitle(strategy),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (strategy != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: episodeSucceeded(episode, day.sessions)
                  ? Text('✓', style: TextStyle(color: scheme.primary))
                  : Text('✗', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          PopupMenuButton<String>(
            key: ValueKey('episode-menu:${episode.id}'),
            icon: Icon(Icons.more_vert, size: 18, color: scheme.onSurfaceVariant),
            onSelected: (_) {
              // Без отмены: эпизод — запись наблюдения, а не работа.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(S.episodeDeleted)),
              );
              context.read<InsightCubit>().deleteEpisode(episode.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(S.delete)),
            ],
          ),
        ],
      ),
    );
  }
}
