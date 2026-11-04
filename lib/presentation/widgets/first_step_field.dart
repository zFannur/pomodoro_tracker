import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../core/failure.dart';
import '../../domain/entities/episode.dart';
import '../../services/ai_service.dart';
import 'ai_consent.dart';

/// Поле «Первый шаг». С ключом DeepSeek — ✨ предлагает три шага чипами.
class FirstStepField extends StatefulWidget {
  const FirstStepField({
    required this.controller,
    this.autofocus = false,
    this.trailing,
    this.ai,
    this.task = '',
    this.category = '',
    this.direction = '',
    this.milestone = '',
    this.cause,
    this.thought = '',
    super.key,
  });

  final TextEditingController controller;
  final bool autofocus;

  /// Своя кнопка справа вместо ✨.
  final Widget? trailing;

  /// null — из дерева ([aiOf]); диалоги передают явно, их маршрут провайдеров
  /// вызывающего экрана не видит.
  final AiService? ai;
  final String task;
  final String category;
  final String direction;
  final String milestone;
  final Cause? cause;
  final String thought;

  @override
  State<FirstStepField> createState() => _FirstStepFieldState();
}

class _FirstStepFieldState extends State<FirstStepField> {
  bool _busy = false;
  List<String> _steps = const [];
  bool _concern = false;

  Future<void> _suggest(AiService ai) async {
    if (!await ensureAiConsent(context, ai) || !mounted) return;
    setState(() => _busy = true);
    final result = await ai.firstSteps(
      task: widget.task,
      category: widget.category,
      direction: widget.direction,
      milestone: widget.milestone,
      cause: widget.cause,
      thought: widget.thought,
    );
    if (!mounted) return;
    result.match(
      (failure) {
        setState(() {
          _busy = false;
          _concern = failure is AiConcern;
          _steps = const [];
        });
        if (failure is! AiConcern) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(failure.message)));
        }
      },
      (steps) => setState(() {
        _busy = false;
        _concern = false;
        _steps = steps;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = widget.ai ?? aiOf(context);
    final canSuggest =
        widget.trailing == null &&
        ai != null &&
        ai.available &&
        widget.task.trim().isNotEmpty;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: S.fieldFirstStep,
            counterText: '',
            suffixIcon:
                widget.trailing ??
                (canSuggest
                    ? AiButton(
                        tooltip: S.aiSuggestStep,
                        busy: _busy,
                        onPressed: () => _suggest(ai),
                      )
                    : null),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (_concern)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              S.aiConcern,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (_steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final step in _steps)
                  ActionChip(
                    label: Text(step),
                    onPressed: () {
                      widget.controller.text = step;
                      setState(() => _steps = const []);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
