import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/markdown_codec.dart'
    show dateHuman, mondayOf, mondayOfSprintId, sprintId, two;
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/direction.dart';
import '../../domain/entities/pomo_session.dart' show logicalDate;
import '../cubits/directions_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../widgets/common.dart';

/// Экран «Курс»: стратегические направления фокуса (3–12 месяцев),
/// лестницы вех, хроника закрытий за 26 недель и бюджет внимания за 30 дней.
/// Каркас повторяет [SprintScreen]: SingleChildScrollView + ConstrainedBox(900).
class CourseScreen extends StatelessWidget {
  const CourseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DirectionsCubit, DirectionsState>(
      builder: (context, state) {
        return switch (state.status) {
          DirectionsStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          DirectionsStatus.failure => ErrorPane(
            message: state.error,
            onRetry: () => context.read<DirectionsCubit>().refresh(),
          ),
          DirectionsStatus.ready => _CourseBody(state: state),
        };
      },
    );
  }
}

class _CourseBody extends StatefulWidget {
  const _CourseBody({required this.state});

  final DirectionsState state;

  @override
  State<_CourseBody> createState() => _CourseBodyState();
}

class _CourseBodyState extends State<_CourseBody> {
  /// Идентификатор раскрытого направления (лестницы вех).
  /// Держится в состоянии экрана, как `_openDay` в [SprintScreen].
  String? _openDirectionId;

  /// Свернуты ли группы «На паузе» и «Закрытые» (по умолчанию свернуты).
  bool _pausedCollapsed = true;
  bool _finishedCollapsed = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final active = state.active;
    final now = DateTime.now();
    final currentMonth = '${now.year}-${two(now.month)}';
    // Месячный разбор показывается раз в месяц при первом открытии экрана «Курс»,
    // если есть направления и за текущий месяц разбор ещё не был закрыт («Понял»).
    final showMonthlyReview =
        state.directions.isNotEmpty && state.reviewedMonth != currentMonth;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Верхняя панель: Заголовок экрана и кнопка создания нового направления
              Row(
                children: [
                  Expanded(
                    child: Text(
                      S.courseDirections,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  // На телефоне подпись кнопки не влезает рядом с заголовком
                  // («Добавить направление» шире всей строки), поэтому там
                  // остаётся только «+» с тултипом.
                  if (MediaQuery.sizeOf(context).width < 600)
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: S.courseAddDirection,
                      onPressed: () => _showAddDirectionDialog(context),
                    )
                  else
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(S.courseAddDirection),
                      onPressed: () => _showAddDirectionDialog(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Баннер месячного разбора
              if (showMonthlyReview) ...[
                _buildMonthlyReviewBanner(context, currentMonth),
                const SizedBox(height: 16),
              ],

              // Пустое состояние, если направлений нет вообще
              if (state.directions.isEmpty)
                SectionCard(
                  title: S.courseDirections,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.courseEmptyDirections,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(S.courseAddDirection),
                        onPressed: () => _showAddDirectionDialog(context),
                      ),
                    ],
                  ),
                )
              else ...[
                // Карточки активных направлений в порядке order
                for (final dir in active) ...[
                  _buildActiveDirectionCard(context, dir),
                  const SizedBox(height: 12),
                ],

                // Мягкая подсказка при перегрузе (> 4 активных фокусов)
                if (active.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      S.tooManyDirections(active.length),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),

                // Секция «На паузе» (свернута по умолчанию)
                if (state.paused.isNotEmpty) ...[
                  _buildCollapsibleSection(
                    title: S.coursePaused,
                    items: state.paused,
                    collapsed: _pausedCollapsed,
                    onToggle: () => setState(
                      () => _pausedCollapsed = !_pausedCollapsed,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Секция «Закрытые» (свернута по умолчанию)
                if (state.finished.isNotEmpty) ...[
                  _buildCollapsibleSection(
                    title: S.courseFinished,
                    items: state.finished,
                    collapsed: _finishedCollapsed,
                    onToggle: () => setState(
                      () => _finishedCollapsed = !_finishedCollapsed,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Лента закрытий за 26 недель
                _buildClosureFeed(context),
                const SizedBox(height: 16),

                // Бюджет внимания за последние 30 дней
                _buildAttentionBudget(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Карточка активного направления с заголовком, контекстным меню,
  /// прогрессом лестницы, следующей вехой, темпом/прогнозом и раскрывающимся списком вех.
  Widget _buildActiveDirectionCard(BuildContext context, Direction dir) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<DirectionsCubit>();
    final isExpanded = _openDirectionId == dir.id;
    final progress = widget.state.progress(dir.id);
    final next = widget.state.next(dir.id);
    final now = DateTime.now();

    // Расчёт темпа и прогноза даты завершения через чистые функции
    final rate = closureRate(widget.state.milestones, dir.id, now);
    final paceText = rate > 0
        ? S.paceLabel(rate.toStringAsFixed(1))
        : S.noPace;
    final eta = directionEta(widget.state.milestones, dir.id, now);
    final etaText = eta != null ? S.etaLabel(dateHuman(eta)) : null;

    // Расчёт доли внимания за 30 дней
    final pomosMap = pomosByDirection(
      widget.state.recentDays,
      widget.state.directions,
    );
    final totalPomos = pomosMap.values.fold<int>(0, (sum, val) => sum + val);
    final dirPomos = pomosMap[dir.id] ?? 0;
    final attentionPercent = totalPomos > 0
        ? (dirPomos * 100 / totalPomos).round()
        : 0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _openDirectionId = isExpanded ? null : dir.id;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Верхняя строка карточки: название крупно + меню ⋮
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dir.name,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      switch (action) {
                        case 'rename':
                          _showRenameDirectionDialog(context, dir);
                        case 'categories':
                          _showCategoriesDialog(context, dir);
                        case 'horizon':
                          _showHorizonDialog(context, dir);
                        case 'note':
                          _showNoteDialog(context, dir);
                        case 'pause':
                          cubit.setStatus(dir.id, DirectionStatus.paused);
                        case 'close':
                          cubit.setStatus(dir.id, DirectionStatus.done);
                        case 'delete':
                          _confirmDeleteDirection(context, dir);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(S.courseRename),
                      ),
                      PopupMenuItem(
                        value: 'categories',
                        child: Text(S.courseCategories),
                      ),
                      PopupMenuItem(
                        value: 'horizon',
                        child: Text(S.courseHorizon),
                      ),
                      PopupMenuItem(
                        value: 'note',
                        child: Text(S.courseObsidianNote),
                      ),
                      PopupMenuItem(
                        value: 'pause',
                        child: Text(S.coursePause),
                      ),
                      PopupMenuItem(
                        value: 'close',
                        child: Text(S.courseCloseDirection),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(S.delete),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Лестница одной строкой: текст прогресса + заметная сегментная полоса
              Row(
                children: [
                  Text(
                    S.ladderProgress(progress.done, progress.total),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MilestoneSegmentBar(
                      done: progress.done,
                      total: progress.total,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Строка следующей вехи: «→ Название» либо «лестница пройдена»
              Text(
                next != null
                    ? '→ ${next.title}'
                    : (progress.total > 0
                        ? S.courseLadderPassed
                        : S.courseEmptyLadder),
                style: next != null
                    ? theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      )
                    : theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Мелкие подписи в ряд: темп, прогноз по дате и доля внимания за 30 дней.
              // Wrap защищает от переполнения на экранах шириной 380px.
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    paceText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (etaText != null)
                    Text(
                      etaText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    '$attentionPercent%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

              // Раскрытая лестница вех
              if (isExpanded) ...[
                const Divider(height: 24),
                _buildMilestonesLadder(context, dir),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Лестница вех внутри раскрытой карточки направления: ReorderableListView,
  /// чекбоксы закрытия/открытия, зачёркнутые закрытые вехи и поле добавления снизу.
  Widget _buildMilestonesLadder(BuildContext context, Direction dir) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<DirectionsCubit>();
    final milestones = ladder(widget.state.milestones, dir.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (milestones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.courseEmptyLadder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: milestones.length,
            onReorderItem: (oldIndex, newIndex) {
              cubit.reorderMilestones(dir.id, oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final m = milestones[index];
              return _MilestoneItemTile(
                key: ValueKey(m.id),
                milestone: m,
                onToggleDone: () {
                  if (m.done) {
                    cubit.reopenMilestone(m.id);
                  } else {
                    final now = DateTime.now();
                    final sId = sprintId(logicalDate(now));
                    cubit.closeMilestone(m.id, sId, now);
                  }
                },
                onRename: () => _showRenameMilestoneDialog(context, m),
                onDelete: () => _confirmDeleteMilestone(context, m),
              );
            },
          ),
        const SizedBox(height: 12),
        _AddMilestoneInput(
          onAdd: (title) => cubit.addMilestone(dir.id, title),
        ),
      ],
    );
  }

  /// Сворачиваемые блоки «На паузе» и «Закрытые» в стиле групп из [TasksScreen].
  Widget _buildCollapsibleSection({
    required String title,
    required List<Direction> items,
    required bool collapsed,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    final cubit = context.read<DirectionsCubit>();

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
                    const SizedBox(width: 8),
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              const Divider(height: 12),
              for (final dir in items)
                _buildCompactDirectionRow(
                  context,
                  dir,
                  onResume: () =>
                      cubit.setStatus(dir.id, DirectionStatus.active),
                  onDelete: () => _confirmDeleteDirection(context, dir),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Компактная строка направления для секций «На паузе» и «Закрытые».
  Widget _buildCompactDirectionRow(
    BuildContext context,
    Direction dir, {
    required VoidCallback onResume,
    required VoidCallback onDelete,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = widget.state.progress(dir.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dir.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            S.ladderProgress(progress.done, progress.total),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            onSelected: (val) {
              if (val == 'resume') {
                onResume();
              } else if (val == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'resume',
                child: Text(S.courseResume),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(S.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Лента закрытий за последние 26 недель в виде горизонтально прокручиваемой сетки.
  /// Строки — активные направления (плюс «Без направления», если были закрытия вне них).
  Widget _buildClosureFeed(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final currentMonday = mondayOf(logicalDate(now));

    // Вычисляем 26 недель слева направо: свежая справа
    final weeks = <({String id, DateTime monday})>[];
    for (var i = 25; i >= 0; i--) {
      final m = currentMonday.subtract(Duration(days: i * 7));
      weeks.add((id: sprintId(m), monday: m));
    }

    final closuresMap = closuresByWeek(widget.state.milestones);
    final activeDirs = widget.state.active;
    final activeIds = activeDirs.map((d) => d.id).toSet();

    // Проверяем, есть ли закрытия вех, не принадлежащих активным направлениям
    final orphanMilestones = widget.state.milestones
        .where((m) => m.done && !activeIds.contains(m.directionId))
        .toList();

    final rows = <({String? id, String name})>[
      for (final d in activeDirs) (id: d.id, name: d.name),
      if (orphanMilestones.isNotEmpty)
        (id: null, name: S.courseThreadNoDirection),
    ];

    const cellSize = 18.0;
    const cellMargin = 2.0;
    const labelWidth = 130.0;

    const ruMonths = [
      '',
      'Янв',
      'Фев',
      'Мар',
      'Апр',
      'Май',
      'Июн',
      'Июл',
      'Авг',
      'Сен',
      'Окт',
      'Ноя',
      'Дек',
    ];
    const enMonths = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final monthsList = S.lang == AppLanguage.ru ? ruMonths : enMonths;

    return SectionCard(
      title: S.courseClosures,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (final w in weeks) ...[
                      Builder(
                        builder: (context) {
                          final weekClosures = closuresMap[w.id] ?? const [];
                          final matching = row.id != null
                              ? weekClosures
                                  .where((m) => m.directionId == row.id)
                                  .toList()
                              : weekClosures
                                  .where(
                                    (m) =>
                                        !activeIds.contains(m.directionId),
                                  )
                                  .toList();
                          final isClosed = matching.isNotEmpty;
                          final tooltip = isClosed
                              ? '${matching.map((m) => m.title).join('\n')} · ${w.id}'
                              : w.id;

                          return Tooltip(
                            message: tooltip,
                            child: Container(
                              width: cellSize,
                              height: cellSize,
                              margin: const EdgeInsets.all(cellMargin),
                              decoration: BoxDecoration(
                                color: isClosed ? scheme.primary : null,
                                border: Border.all(
                                  color: isClosed
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 6),
            // Месячные подписи под колонками недель
            Row(
              children: [
                const SizedBox(width: labelWidth + 8),
                for (var i = 0; i < weeks.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final w = weeks[i];
                      final isNewMonth =
                          i == 0 || w.monday.month != weeks[i - 1].monday.month;
                      return Container(
                        width: cellSize + cellMargin * 2,
                        alignment: Alignment.centerLeft,
                        child: isNewMonth
                            ? Text(
                                monthsList[w.monday.month],
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              )
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Бюджет внимания: горизонтальные полосы распределения помидоров за 30 дней
  /// с объявленным приоритетом (#1, #2, ...) и строкой «Без направления» в конце.
  Widget _buildAttentionBudget(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pomosMap = pomosByDirection(
      widget.state.recentDays,
      widget.state.directions,
    );
    final totalPomos = pomosMap.values.fold<int>(0, (sum, val) => sum + val);
    final activeDirs = widget.state.active;

    return SectionCard(
      title: S.courseAttention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < activeDirs.length; i++) ...[
            Builder(
              builder: (context) {
                final dir = activeDirs[i];
                final dirPomos = pomosMap[dir.id] ?? 0;
                final fraction =
                    totalPomos > 0 ? (dirPomos / totalPomos) : 0.0;
                final percent = (fraction * 100).round();

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${i + 1} ',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              dir.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$dirPomos 🍅 · $percent%',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(scheme.primary),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          // Последняя строка — вне направлений
          Builder(
            builder: (context) {
              final extraPomos = pomosMap[''] ?? 0;
              final fraction =
                  totalPomos > 0 ? (extraPomos / totalPomos) : 0.0;
              final percent = (fraction * 100).round();

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            S.courseThreadNoDirection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$extraPomos 🍅 · $percent%',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(scheme.outline),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Диалоги направлений
  // ---------------------------------------------------------------------------

  void _showAddDirectionDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.courseAddDirection),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.courseDirection,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(S.add),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty && context.mounted) {
        context.read<DirectionsCubit>().addDirection(name);
      }
    }).whenComplete(controller.dispose);
  }

  void _showRenameDirectionDialog(BuildContext context, Direction dir) {
    final controller = TextEditingController(text: dir.name);
    showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.courseRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.courseDirection,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(S.save),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty && context.mounted) {
        context.read<DirectionsCubit>().updateDirection(
              dir.copyWith(name: name),
            );
      }
    }).whenComplete(controller.dispose);
  }

  void _showCategoriesDialog(BuildContext context, Direction dir) {
    final settingsCubit = context.read<SettingsCubit>();
    final knownCategories =
        settingsCubit.state.settings.categories.keys.toList();
    final selected = {...dir.categories};
    final controller = TextEditingController();

    showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final allCatList = {...knownCategories, ...selected}.toList()..sort();
          return AlertDialog(
            title: Text(S.courseCategories),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final cat in allCatList)
                        FilterChip(
                          label: Text(cat),
                          selected: selected.contains(cat),
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selected.add(cat);
                              } else {
                                selected.remove(cat);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: S.newCategory,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          final cat = controller.text.trim();
                          if (cat.isNotEmpty) {
                            registerCategory(settingsCubit, cat);
                            setModalState(() {
                              selected.add(cat);
                            });
                            controller.clear();
                          }
                        },
                        child: Text(S.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(S.cancel),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(selected.toList()),
                child: Text(S.save),
              ),
            ],
          );
        },
      ),
    ).then((result) {
      if (result != null && context.mounted) {
        context.read<DirectionsCubit>().updateDirection(
              dir.copyWith(categories: result),
            );
      }
    }).whenComplete(controller.dispose);
  }

  void _showHorizonDialog(BuildContext context, Direction dir) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.courseHorizon),
        content: Text(
          dir.horizon != null
              ? dateHuman(dir.horizon!)
              : S.courseNoHorizon,
        ),
        actions: [
          if (dir.horizon != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.courseNoHorizon),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.chooseFolder.replaceAll('…', '')),
          ),
        ],
      ),
    ).then((pickDate) {
      if (!context.mounted || pickDate == null) return;
      if (!pickDate) {
        context.read<DirectionsCubit>().updateDirection(
              dir.copyWith(clearHorizon: true),
            );
        return;
      }
      final now = DateTime.now();
      showDatePicker(
        context: context,
        initialDate: dir.horizon ?? now,
        firstDate: DateTime(now.year - 1, 1, 1),
        lastDate: DateTime(now.year + 10, 12, 31),
      ).then((picked) {
        if (context.mounted && picked != null) {
          context.read<DirectionsCubit>().updateDirection(
                dir.copyWith(horizon: picked),
              );
        }
      });
    });
  }

  void _showNoteDialog(BuildContext context, Direction dir) {
    final controller = TextEditingController(text: dir.note);
    showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.courseObsidianNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.courseObsidianNote,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(S.save),
          ),
        ],
      ),
    ).then((note) {
      if (note != null && context.mounted) {
        context.read<DirectionsCubit>().updateDirection(
              dir.copyWith(note: note),
            );
      }
    }).whenComplete(controller.dispose);
  }

  void _confirmDeleteDirection(BuildContext context, Direction dir) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.delete),
        content: Text(S.deleteDirectionConfirm(dir.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.delete),
          ),
        ],
      ),
    ).then((confirm) {
      if (confirm == true && context.mounted) {
        context.read<DirectionsCubit>().deleteDirection(dir.id);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Диалоги вех
  // ---------------------------------------------------------------------------

  void _showRenameMilestoneDialog(BuildContext context, Milestone m) {
    final controller = TextEditingController(text: m.title);
    showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.courseRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.courseMilestone,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(S.save),
          ),
        ],
      ),
    ).then((title) {
      if (title != null && title.isNotEmpty && context.mounted) {
        context.read<DirectionsCubit>().updateMilestone(
              m.copyWith(title: title),
            );
      }
    }).whenComplete(controller.dispose);
  }

  void _confirmDeleteMilestone(BuildContext context, Milestone m) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.delete),
        content: Text(S.courseDeleteMilestoneConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.delete),
          ),
        ],
      ),
    ).then((confirm) {
      if (confirm == true && context.mounted) {
        context.read<DirectionsCubit>().deleteMilestone(m.id);
      }
    });
  }

  /// Баннер месячного разбора: показывается раз в месяц при первом открытии экрана «Курс».
  /// Подводит итог закрытий за месяц и выявляет застрявшие направления (>6 недель без движения).
  Widget _buildMonthlyReviewBanner(BuildContext context, String currentMonth) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<DirectionsCubit>();
    final now = DateTime.now();

    // 1. Закрыто вех за последние 30 дней
    final cutoff30 = now.subtract(const Duration(days: 30));
    var closedCount = 0;
    for (final m in widget.state.milestones) {
      if (!m.done) continue;
      if (m.doneAt != null) {
        if (!m.doneAt!.isBefore(cutoff30) && !m.doneAt!.isAfter(now)) {
          closedCount++;
        }
      } else {
        final monday = mondayOfSprintId(m.doneSprint);
        if (monday != null && !monday.isBefore(cutoff30)) {
          closedCount++;
        }
      }
    }

    // 2. Активные направления без движения за последние 6 недель
    final cutoff6Weeks = now.subtract(const Duration(days: 42));
    final stale = <({Direction dir, int weeks})>[];
    for (final dir in widget.state.active) {
      final dirMilestones = ladder(widget.state.milestones, dir.id);
      DateTime? latestDone;
      for (final m in dirMilestones) {
        if (!m.done) continue;
        final date = m.doneAt ?? mondayOfSprintId(m.doneSprint);
        if (date != null && (latestDone == null || date.isAfter(latestDone))) {
          latestDone = date;
        }
      }
      if (latestDone == null || latestDone.isBefore(cutoff6Weeks)) {
        final weeks = latestDone == null
            ? 6
            : (now.difference(latestDone).inDays ~/ 7).clamp(6, 999);
        stale.add((dir: dir, weeks: weeks));
      }
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_graph, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.monthReviewTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => cubit.dismissMonthReview(currentMonth),
                  child: Text(S.monthReviewDismiss),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              S.monthReviewClosed(closedCount),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stale.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final item in stale) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    S.monthReviewStale(item.dir.name, item.weeks),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () => cubit.setStatus(
                        item.dir.id,
                        DirectionStatus.paused,
                      ),
                      child: Text(S.toPause),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        final sorted = [...widget.state.directions]
                          ..sort((a, b) => a.order.compareTo(b.order));
                        final idx =
                            sorted.indexWhere((d) => d.id == item.dir.id);
                        if (idx > 0) cubit.reorderDirections(idx, 0);
                      },
                      child: Text(S.makeNumberOne),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Визуальная полоса сегментов лестницы вех направления.
/// Закрытые вехи залиты primary, открытые — surfaceContainerHighest.
class _MilestoneSegmentBar extends StatelessWidget {
  const _MilestoneSegmentBar({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return SizedBox(
      height: 8,
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
                decoration: BoxDecoration(
                  color: i < done
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка отдельной вехи внутри лестницы: чекбокс, текст (зачёркнутый если закрыта),
/// спринт закрытия справа и контекстное меню ⋮ (переименовать/удалить).
class _MilestoneItemTile extends StatelessWidget {
  const _MilestoneItemTile({
    required this.milestone,
    required this.onToggleDone,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final Milestone milestone;
  final VoidCallback onToggleDone;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onLongPress: onRename,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: milestone.done,
              onChanged: (_) => onToggleDone(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    milestone.title,
                    style: milestone.done
                        ? theme.textTheme.bodyMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: scheme.onSurfaceVariant,
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                  if (milestone.proofs.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    for (final proof in milestone.proofs)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          proof,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (milestone.done && milestone.doneSprint.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                milestone.doneSprint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (action) {
                if (action == 'rename') {
                  onRename();
                } else if (action == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(S.courseRename),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(S.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Поле добавления новой вехи: TextField с кнопкой «Добавить», реагирует на Enter.
class _AddMilestoneInput extends StatefulWidget {
  const _AddMilestoneInput({required this.onAdd});

  final void Function(String title) onAdd;

  @override
  State<_AddMilestoneInput> createState() => _AddMilestoneInputState();
}

class _AddMilestoneInputState extends State<_AddMilestoneInput> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onAdd(text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: S.courseAddMilestone,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _submit,
          icon: const Icon(Icons.add, size: 18),
          label: Text(S.add),
        ),
      ],
    );
  }
}
