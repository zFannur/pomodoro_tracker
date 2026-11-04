import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../cubits/insight_cubit.dart';

/// Шкала IPS: 9 утверждений по 5 вариантов. «Сохранить» — когда отвечены все.
/// Обратные пункты не переворачиваем при записи: хранятся ответы как есть,
/// сумма считается в `ipsScore`.
Future<void> showIpsDialog(BuildContext context) {
  // Кубит — до showDialog: контекст диалога не наследует провайдеры экрана.
  final insight = context.read<InsightCubit>();
  return showDialog<void>(
    context: context,
    builder: (_) => _IpsDialog(insight: insight),
  );
}

class _IpsDialog extends StatefulWidget {
  const _IpsDialog({required this.insight});

  final InsightCubit insight;

  @override
  State<_IpsDialog> createState() => _IpsDialogState();
}

class _IpsDialogState extends State<_IpsDialog> {
  final _answers = List<int?>.filled(9, null);

  bool get _complete => _answers.every((a) => a != null);

  Future<void> _save() async {
    await widget.insight.saveIps([for (final a in _answers) a!]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(S.ipsTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${S.ipsLow}\n${S.ipsHigh}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (var i = 0; i < 9; i++) ...[
                const SizedBox(height: 16),
                Text('${i + 1}. ${S.ipsItem(i)}'),
                const SizedBox(height: 6),
                // Wrap, а не Row: на узком телефоне пять чипов переносятся.
                Wrap(
                  spacing: 6,
                  children: [
                    for (var n = 1; n <= 5; n++)
                      ChoiceChip(
                        key: ValueKey('ips:$i:$n'),
                        label: Text('$n'),
                        showCheckmark: false,
                        selected: _answers[i] == n,
                        onSelected: (_) => setState(() => _answers[i] = n),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed: _complete ? _save : null,
          child: Text(S.save),
        ),
      ],
    );
  }
}
