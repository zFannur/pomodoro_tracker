import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../services/ai_service.dart';

/// Сервис ИИ из дерева или null: без провайдера (старые тесты, диалоги без
/// проброса) ✨ просто не показывается — приложение работает как без ключа.
/// Nullable-тип provider ищет без исключения.
AiService? aiOf(BuildContext context) =>
    RepositoryProvider.of<AiService?>(context);

/// Одноразовое предупреждение перед первым запросом в DeepSeek.
/// true — можно отправлять.
Future<bool> ensureAiConsent(BuildContext context, AiService ai) async {
  if (ai.consented) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(S.aiConsentText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(S.aiConsentYes),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await ai.grantConsent();
  return ai.consented;
}

/// Кнопка ✨ с индикатором на время запроса.
class AiButton extends StatelessWidget {
  const AiButton({
    required this.tooltip,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome),
  );
}
