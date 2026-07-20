import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/markdown_codec.dart';
import '../cubits/stats_cubit.dart';
import '../widgets/common.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatsCubit, StatsState>(
      builder: (context, state) {
        return switch (state.status) {
          StatsStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          StatsStatus.failure => ErrorPane(
            message: state.error,
            onRetry: () => context.read<StatsCubit>().refresh(),
          ),
          StatsStatus.ready => _StatsBody(state: state),
        };
      },
    );
  }
}

/// Плитки статистики по [perRow] в ряд. StatTile — Expanded, поэтому живёт
/// только внутри Row; неполный последний ряд добиваем пустотой, иначе
/// одинокая плитка растянулась бы на всю ширину.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles, required this.perRow});

  final List<Widget> tiles;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += perRow) {
      final slice = tiles.skip(i).take(perRow).toList();
      rows.add(
        // Без CrossAxisAlignment.stretch: высота внутри прокручиваемой
        // колонки не ограничена, растягивание даёт бесконечность и рушит
        // всю раскладку экрана.
        Row(
          children: [
            for (var j = 0; j < slice.length; j++) ...[
              if (j > 0) const SizedBox(width: 8),
              slice[j],
            ],
            for (var j = slice.length; j < perRow; j++) ...[
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.state});

  final StatsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byCategory = state.byCategory;
    final maxCategory = byCategory.values.fold(
      1,
      (max, v) => v > max ? v : max,
    );
    final best = state.bestDay;
    final showHeatmap = state.periodDays.length >= 90;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 5 сегментов не влезают в ширину телефона — даём прокрутку,
              // иначе подписи ужимаются до букв в столбик.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<StatsPeriod>(
                  segments: [
                    ButtonSegment(
                      value: StatsPeriod.today,
                      label: Text(S.periodToday),
                    ),
                    ButtonSegment(
                      value: StatsPeriod.week,
                      label: Text(S.periodWeek),
                    ),
                    ButtonSegment(
                      value: StatsPeriod.month,
                      label: Text(S.periodMonth),
                    ),
                    ButtonSegment(
                      value: StatsPeriod.year,
                      label: Text(S.periodYear),
                    ),
                    ButtonSegment(
                      value: StatsPeriod.custom,
                      label: Text(S.periodCustom),
                    ),
                  ],
                  selected: {state.period},
                  onSelectionChanged: (selection) async {
                    final cubit = context.read<StatsCubit>();
                    final period = selection.first;
                    if (period == StatsPeriod.custom) {
                      final now = DateTime.now();
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 3),
                        lastDate: now,
                      );
                      if (range != null) {
                        await cubit.setPeriod(
                          period,
                          from: range.start,
                          to: range.end,
                        );
                      }
                      return;
                    }
                    await cubit.setPeriod(period);
                  },
                ),
              ),
              const SizedBox(height: 16),
              // На телефоне пять плиток в одну строку дают по ~60dp на каждую —
              // подписи превращаются в «По…». Раскладываем по две в ряд.
              _StatGrid(
                perRow: MediaQuery.sizeOf(context).width < 600 ? 2 : 5,
                tiles: [
                  StatTile(
                    label: S.statPomodoros,
                    value: '${state.periodPomodoros} 🍅',
                  ),
                  StatTile(
                    label: S.statTime,
                    value: formatMinutesUi(state.periodMinutes),
                  ),
                  StatTile(label: S.statFocus, value: '${state.periodFocus}%'),
                  // Мягкая стата: дней с лягушкой из активных дней. Без стрика —
                  // «текущей серии» здесь намеренно нет.
                  StatTile(
                    label: S.statFrog,
                    value: state.activeDays == 0
                        ? '—'
                        : '${state.frogDays} / ${state.activeDays}',
                  ),
                  // ponytail: плитки «Серия дней» нет сознательно — рваный стрик
                  // кормит самокритику (см. систему фокуса пользователя).
                  StatTile(
                    label: S.statBestDay,
                    value: best == null
                        ? '—'
                        : '${dateHuman(best.date)} · ${best.count} 🍅',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.periodPomodoros == 0)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    S.statEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                SectionCard(
                  title: S.statByCategory,
                  child: Column(
                    children: [
                      for (final entry in byCategory.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: CategoryChip(entry.key),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: entry.value / maxCategory,
                                    minHeight: 14,
                                    color: AppTheme.categoryColor(entry.key),
                                    backgroundColor: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${entry.value}',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (showHeatmap) ...[
                SectionCard(
                  title: S.statHeatmap,
                  child: HeatmapCalendar(days: state.periodDays),
                ),
                const SizedBox(height: 12),
              ],
              SectionCard(
                title: S.statLast14,
                child: DaysBarChart(
                  days: state.last14,
                  goal: state.goal,
                  height: 140,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
