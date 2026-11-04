import 'package:flutter/material.dart';

import '../../app/strings.dart';

class DeferralsBadge extends StatelessWidget {
  const DeferralsBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: S.deferralsTooltip(count),
      child: Text(
        S.deferralsBadge(count),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }
}
