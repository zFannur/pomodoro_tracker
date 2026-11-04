import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../domain/entities/episode.dart';

class CauseChips extends StatelessWidget {
  const CauseChips({
    required this.onSelected,
    this.selected,
    this.includeFinished = false,
    this.finished = false,
    this.onFinished,
    super.key,
  });

  final Cause? selected;
  final ValueChanged<Cause?> onSelected;
  final bool includeFinished;
  final bool finished;
  final VoidCallback? onFinished;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final cause in Cause.values)
        ChoiceChip(
          label: Text(S.cause(cause), softWrap: true),
          selected: !finished && selected == cause,
          onSelected: (value) => onSelected(value ? cause : null),
        ),
      if (includeFinished)
        ChoiceChip(
          label: Text(S.causeFinished),
          selected: finished,
          onSelected: (_) => onFinished?.call(),
        ),
    ],
  );
}
