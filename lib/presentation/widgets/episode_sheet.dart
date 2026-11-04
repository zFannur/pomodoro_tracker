import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../core/failure.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/pomo_task.dart';
import '../../services/ai_service.dart';
import '../cubits/directions_cubit.dart';
import '../cubits/insight_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../cubits/timer_cubit.dart';
import 'ai_consent.dart';
import 'cause_chips.dart';
import 'first_step_field.dart';

Future<void> showEpisodeSheet(
  BuildContext context, {
  required EpisodeSource source,
  PomoTask? task,
  Episode? existing,
}) {
  // Контекст маршрута не наследует провайдеры вызывающего экрана.
  final insight = context.read<InsightCubit>();
  final tasks = context.read<TasksCubit>();
  final timer = context.read<TimerCubit>();
  final directions = context.read<DirectionsCubit>();
  final ai = aiOf(context);
  final content = _EpisodeSheet(
    source: source,
    task: task,
    existing: existing,
    insight: insight,
    tasks: tasks,
    timer: timer,
    directions: directions,
    ai: ai,
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => content,
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(child: SizedBox(width: 460, child: content)),
  );
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet({
    required this.source,
    required this.task,
    required this.existing,
    required this.insight,
    required this.tasks,
    required this.timer,
    required this.directions,
    this.ai,
  });

  final EpisodeSource source;
  final PomoTask? task;
  final Episode? existing;
  final InsightCubit insight;
  final TasksCubit tasks;
  final TimerCubit timer;
  final DirectionsCubit directions;
  final AiService? ai;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  late final _firstStep = TextEditingController(text: widget.task?.firstStep);
  late final _draft = _StrategyDraft(
    thought: widget.existing?.thought ?? '',
    cue: widget.task?.cue ?? '',
    cueAt: widget.task?.cueAt ?? '',
    fact: widget.existing?.fact ?? '',
    alt: widget.existing?.alt ?? '',
  );
  late Episode? _episode = widget.existing;
  late Cause? _cause = widget.existing?.cause;
  StrategyKind? _kind;
  bool _chosen = false;
  bool _help = false;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _firstStep.dispose();
    super.dispose();
  }

  Future<bool> _saveCause(Cause cause) async {
    final existing = _episode;
    if (existing == null) {
      final episode = await widget.insight.addEpisode(
        source: widget.source,
        task: widget.task,
        cause: cause,
        thought: _draft.thought.trim(),
      );
      if (widget.insight.state.status != InsightStatus.failure) {
        _episode = episode;
      }
    } else {
      await widget.insight.setCause(
        existing.id,
        cause,
        thought: _draft.thought.trim(),
      );
    }
    return widget.insight.state.status != InsightStatus.failure;
  }

  Future<void> _choose(Cause? cause) async {
    if (cause == null || _busy) return;
    setState(() {
      _busy = true;
      _cause = cause;
      _error = '';
    });
    final saved = await _saveCause(cause);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _chosen = saved;
      _kind = null;
      _error = saved ? '' : widget.insight.state.error;
    });
  }

  Future<void> _mark() async {
    if (_busy) return;
    final cause = _cause;
    if (cause == null) return;
    setState(() => _busy = true);
    final saved = await _saveCause(cause);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = widget.insight.state.error;
      });
    }
  }

  List<StrategyKind> _ranked(Cause cause) => widget.insight
      .ranked(cause)
      .where(
        (k) =>
            widget.task != null ||
            !{
              StrategyKind.firstStep,
              StrategyKind.ifThen,
              StrategyKind.shrink,
            }.contains(k),
      )
      .toList();

  Future<void> _activateTask() async {
    final task = widget.task;
    if (task == null || !widget.timer.state.stopped) return;
    final planner = widget.tasks.plannerIndexOf(task);
    if (planner >= 0) await widget.tasks.plannerToToday(planner);
    if (widget.tasks.state.status == TasksStatus.failure) return;
    final index = widget.tasks.todoIndexOf(task);
    if (index > 0) await widget.tasks.reorder(index, 0);
  }

  Future<void> _act(
    StrategyKind kind, {
    bool start = true,
    bool inbox = false,
  }) async {
    final episode = _episode;
    final cause = _cause;
    if (_busy || episode == null || cause == null) return;
    final firstStep = _firstStep.text.trim();
    setState(() {
      _busy = true;
      _error = '';
    });
    // Мысль можно уточнить в карточке КПТ перед сохранением способа.
    if (!await _saveCause(cause)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.insight.state.error;
        });
      }
      return;
    }
    await widget.insight.setStrategy(
      episode.id,
      kind,
      fact: _draft.fact.trim(),
      alt: _draft.alt.trim(),
    );
    if (widget.insight.state.status == InsightStatus.failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.insight.state.error;
        });
      }
      return;
    }
    final task = widget.task;
    final tasks = widget.tasks;
    final timer = widget.timer;
    switch (kind) {
      case StrategyKind.firstStep || StrategyKind.ifThen:
        final id = task?.id;
        if (id != null && id.isNotEmpty) {
          await tasks.setPlan(
            id,
            firstStep: firstStep,
            cue: kind == StrategyKind.ifThen ? _draft.cue.trim() : null,
            cueAt: kind == StrategyKind.ifThen ? _draft.cueAt : null,
          );
        } else if (task != null) {
          // Старые задачи без id ищутся по identity, как в редакторе.
          final index = tasks.todoIndexOf(task);
          if (index >= 0) {
            await tasks.edit(
              index,
              firstStep: firstStep,
              cue: kind == StrategyKind.ifThen ? _draft.cue.trim() : null,
              cueAt: kind == StrategyKind.ifThen ? _draft.cueAt : null,
            );
          } else {
            final index = tasks.plannerIndexOf(task);
            if (index >= 0) {
              await tasks.plannerEdit(
                index,
                firstStep: firstStep,
                cue: kind == StrategyKind.ifThen ? _draft.cue.trim() : null,
                cueAt: kind == StrategyKind.ifThen ? _draft.cueAt : null,
              );
            }
          }
        }
      case StrategyKind.shrink:
        // Не подменяем текущую задачу у уже идущего помидора.
        if (task != null && !timer.state.running) {
          if (timer.state.paused) timer.stop();
          await tasks.addSmaller(task, _draft.smaller);
        }
      case StrategyKind.value:
        final direction = widget.directions.state.directionForCategory(
          task?.category ?? '',
        );
        if (direction != null &&
            direction.why.trim().isEmpty &&
            _draft.why.trim().isNotEmpty) {
          await widget.directions.updateDirection(
            direction.copyWith(why: _draft.why.trim()),
          );
        }
        if (inbox && task != null) {
          if (timer.state.paused) timer.stop();
          final index = tasks.todoIndexOf(task);
          if (index >= 0) {
            await tasks.postpone(index, PlannerTab.inbox, countDeferral: false);
          } else {
            final index = tasks.plannerIndexOf(task);
            if (index >= 0 && tasks.state.planner[index].due != null) {
              // Возврат к переоценке цели — не откладывание из-за срока.
              await tasks.plannerMove(
                index,
                PlannerTab.inbox,
                countDeferral: false,
              );
            }
          }
        }
      case StrategyKind.removeCue:
        if (_draft.inbox.trim().isNotEmpty) {
          await tasks.add(
            _draft.inbox,
            fallbackCategory: task?.category ?? '',
            toPlanner: true,
          );
        }
      case StrategyKind.warmup ||
          StrategyKind.thought ||
          StrategyKind.defuse ||
          StrategyKind.rest:
        break;
    }
    final failure = tasks.state.status == TasksStatus.failure
        ? tasks.state.error
        : widget.directions.state.status == DirectionsStatus.failure
        ? widget.directions.state.error
        : '';
    if (failure.isNotEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure;
        });
      }
      return;
    }
    if (start && !inbox && !timer.state.running) {
      if (kind != StrategyKind.shrink && kind != StrategyKind.rest) {
        await _activateTask();
      }
      if (tasks.state.status != TasksStatus.failure) {
        if (kind == StrategyKind.rest) {
          if (timer.state.paused) timer.stop();
          timer.startRest(10);
        } else if (kind == StrategyKind.removeCue ||
            kind == StrategyKind.shrink) {
          if (timer.state.paused) {
            timer.resume();
          } else {
            timer.start();
          }
        } else {
          timer.startWarmup(10);
        }
      }
    }
    if (!mounted) return;
    if (tasks.state.status == TasksStatus.failure) {
      setState(() {
        _busy = false;
        _error = tasks.state.error;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cause = _cause;
    final observation = _chosen && widget.insight.observation && !_help;
    final ranked = cause == null ? <StrategyKind>[] : _ranked(cause);
    final kind = _kind ?? ranked.firstOrNull;
    final strategies = _chosen && !observation;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: AbsorbPointer(
          absorbing: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strategies ? S.episodeTry : S.episodeTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: S.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if ((widget.task?.description ?? widget.existing?.task ?? '')
                  .isNotEmpty)
                Text(widget.task?.description ?? widget.existing?.task ?? ''),
              const SizedBox(height: 12),
              if (!_chosen) ...[
                CauseChips(selected: cause, onSelected: _choose),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _draft.thought,
                  decoration: InputDecoration(labelText: S.episodeThought),
                  onChanged: (v) => _draft.thought = v,
                ),
              ] else if (observation) ...[
                Text(S.observationNote),
                TextButton(
                  onPressed: () => setState(() => _help = true),
                  child: Text(S.observationHelp),
                ),
                FilledButton(onPressed: _mark, child: Text(S.episodeDone)),
              ] else if (kind != null) ...[
                _StrategyCard(
                  kind: kind,
                  cause: cause,
                  ai: widget.ai,
                  task: widget.task,
                  draft: _draft,
                  firstStep: _firstStep,
                  directions: widget.directions,
                  running: widget.timer.state.running,
                  onAction: _act,
                  onChanged: () => setState(() {}),
                ),
                if (widget.insight.stats[kind] case final stats?
                    when stats.tries >= 3)
                  Text(S.episodeHelped(stats.wins, stats.tries)),
                if (ranked.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(S.episodeOther),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final other in ranked.where((k) => k != kind))
                        ActionChip(
                          label: Text(S.strategyTitle(other)),
                          onPressed: () => setState(() => _kind = other),
                        ),
                    ],
                  ),
                ],
              ] else
                Text(S.episodeNoStrategies),
              if (!observation)
                TextButton(
                  onPressed: cause == null ? null : _mark,
                  child: Text(S.episodeJustMark),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                Text(
                  '${S.errorPrefix}$_error',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrategyDraft {
  _StrategyDraft({
    required this.thought,
    required this.cue,
    required this.cueAt,
    required this.fact,
    required this.alt,
  });
  String thought;
  String cue;
  String cueAt;
  String fact;
  String alt;
  String smaller = '';
  String why = '';
  String inbox = '';
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.kind,
    required this.cause,
    required this.ai,
    required this.task,
    required this.draft,
    required this.firstStep,
    required this.directions,
    required this.running,
    required this.onAction,
    required this.onChanged,
  });

  final StrategyKind kind;
  final Cause? cause;
  final AiService? ai;
  final PomoTask? task;
  final _StrategyDraft draft;
  final TextEditingController firstStep;
  final DirectionsCubit directions;
  final bool running;
  final Future<void> Function(StrategyKind, {bool start, bool inbox}) onAction;
  final VoidCallback onChanged;

  Widget _field(String label, String value, ValueChanged<String> change) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          key: ValueKey(label),
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            change(v);
            onChanged();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = directions.state.directionForCategory(
      task?.category ?? '',
    );
    final valid = switch (kind) {
      StrategyKind.firstStep => firstStep.text.trim().isNotEmpty,
      StrategyKind.ifThen =>
        firstStep.text.trim().isNotEmpty && draft.cue.trim().isNotEmpty,
      StrategyKind.shrink => draft.smaller.trim().isNotEmpty || running,
      _ => true,
    };
    final label = running
        ? S.actionContinue
        : switch (kind) {
            StrategyKind.firstStep ||
            StrategyKind.thought ||
            StrategyKind.ifThen => S.actionSaveWarmup,
            StrategyKind.shrink => S.actionAddStart,
            StrategyKind.rest => S.actionRest,
            StrategyKind.removeCue => S.actionContinue,
            _ => S.actionWarmup,
          };
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.strategyTitle(kind), style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(S.strategyBody(kind), style: theme.textTheme.bodySmall),
            if (kind == StrategyKind.firstStep ||
                kind == StrategyKind.ifThen) ...[
              const SizedBox(height: 12),
              if (kind == StrategyKind.firstStep ||
                  (task?.firstStep.trim().isEmpty ?? true))
                FirstStepField(
                  controller: firstStep,
                  ai: ai,
                  task: task?.description ?? '',
                  category: task?.category ?? '',
                  direction: direction?.name ?? '',
                  milestone: direction == null
                      ? ''
                      : directions.state.next(direction.id)?.title ?? '',
                  cause: cause,
                  thought: draft.thought,
                )
              else
                Text('${S.fieldThen} ${firstStep.text}'),
            ],
            if (kind == StrategyKind.ifThen) ...[
              _field(S.fieldCue, draft.cue, (v) => draft.cue = v),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: Text(
                      '${S.fieldCueAt}${draft.cueAt.isEmpty ? '' : ' ${draft.cueAt}'}',
                    ),
                    avatar: const Icon(Icons.schedule, size: 18),
                    onPressed: () async {
                      final parts = draft.cueAt.split(':');
                      final time = await showTimePicker(
                        context: context,
                        initialTime: parts.length == 2
                            ? TimeOfDay(
                                hour: int.parse(parts[0]),
                                minute: int.parse(parts[1]),
                              )
                            : TimeOfDay.fromDateTime(clock.now()),
                      );
                      if (!context.mounted || time == null) return;
                      draft.cueAt =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      onChanged();
                    },
                  ),
                  if (draft.cueAt.isNotEmpty)
                    IconButton(
                      tooltip: S.delete,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        draft.cueAt = '';
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
            if (kind == StrategyKind.shrink && !running)
              _field(S.fieldShrink, draft.smaller, (v) => draft.smaller = v),
            if (kind == StrategyKind.thought) ...[
              _field(S.fieldThought, draft.thought, (v) => draft.thought = v),
              _field(S.fieldFact, draft.fact, (v) => draft.fact = v),
              _AltField(
                draft: draft,
                ai: ai,
                cause: cause,
                task: task?.description ?? '',
                onChanged: onChanged,
              ),
            ],
            if (kind == StrategyKind.defuse && draft.thought.trim().isNotEmpty)
              Text(S.defuseLine(draft.thought)),
            if (kind == StrategyKind.value)
              if (direction == null)
                Text(S.valueNoDirection)
              else if (direction.why.trim().isEmpty)
                _field(S.fieldWhy, draft.why, (v) => draft.why = v)
              else
                Text(direction.why),
            if (kind == StrategyKind.removeCue)
              _field(S.fieldToInbox, draft.inbox, (v) => draft.inbox = v),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: firstStep,
              builder: (_, _) {
                final enabled =
                    (kind == StrategyKind.firstStep ||
                        kind == StrategyKind.ifThen)
                    ? firstStep.text.trim().isNotEmpty &&
                          (kind != StrategyKind.ifThen ||
                              draft.cue.trim().isNotEmpty)
                    : valid;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: enabled ? () => onAction(kind) : null,
                      child: Text(label),
                    ),
                    if (kind == StrategyKind.ifThen && !running)
                      TextButton(
                        onPressed: enabled
                            ? () => onAction(kind, start: false)
                            : null,
                        child: Text(S.actionSave),
                      ),
                    if (kind == StrategyKind.value &&
                        direction == null &&
                        task != null &&
                        !running)
                      TextButton(
                        onPressed: () =>
                            onAction(kind, start: false, inbox: true),
                        child: Text(S.actionToInbox),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// «Как сказать точнее» с ✨: reframe заполняет поле, над ним — паттерн
/// мысли и сократовский вопрос. Без ключа — обычное поле.
class _AltField extends StatefulWidget {
  const _AltField({
    required this.draft,
    required this.ai,
    required this.cause,
    required this.task,
    required this.onChanged,
  });

  final _StrategyDraft draft;
  final AiService? ai;
  final Cause? cause;
  final String task;
  final VoidCallback onChanged;

  @override
  State<_AltField> createState() => _AltFieldState();
}

class _AltFieldState extends State<_AltField> {
  late final _controller = TextEditingController(text: widget.draft.alt);
  bool _busy = false;
  Reframe? _hint;
  bool _concern = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reframe(AiService ai) async {
    if (!await ensureAiConsent(context, ai) || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final result = await ai.reframe(
      thought: widget.draft.thought.trim(),
      cause: widget.cause,
      task: widget.task,
    );
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _busy = false;
        _hint = null;
        _concern = failure is AiConcern;
        _error = failure is AiConcern ? '' : failure.message;
      }),
      (hint) {
        setState(() {
          _busy = false;
          _concern = false;
          _hint = hint;
          if (hint.alternative.isNotEmpty) {
            _controller.text = hint.alternative;
            widget.draft.alt = hint.alternative;
          }
        });
        widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ai = widget.ai;
    final hint = _hint;
    final canSuggest =
        ai != null && ai.available && widget.draft.thought.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_concern)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(S.aiConcern, style: muted),
            )
          else if (hint != null) ...[
            if (hint.pattern != 'none')
              Text(
                S.thinkingPattern(S.thinkingPatternName(hint.pattern)),
                style: theme.textTheme.labelMedium,
              ),
            if (hint.question.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(hint.question, style: muted),
              ),
          ],
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: S.fieldAlt,
              border: const OutlineInputBorder(),
              suffixIcon: canSuggest
                  ? AiButton(
                      tooltip: S.aiSuggestThought,
                      busy: _busy,
                      onPressed: () => _reframe(ai),
                    )
                  : null,
            ),
            onChanged: (v) {
              widget.draft.alt = v;
              widget.onChanged();
            },
          ),
          if (_error.isNotEmpty)
            Text(
              _error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
