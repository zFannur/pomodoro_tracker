import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../domain/entities/app_settings.dart';

/// Уведомления: системные тосты Windows, поднятие окна,
/// пересылка в Telegram через своего бота.
class NotifyService {
  bool _ready = false;
  final math.Random _random = math.Random();
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Future<void> init(String appName) async {
    await localNotifier.setup(appName: appName);
    _ready = true;
  }

  /// Случайная строка из кастомного многострочного сообщения;
  /// пусто — [fallback].
  String pickMessage(String custom, String fallback) {
    final lines = custom
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return fallback;
    return lines[_random.nextInt(lines.length)];
  }

  /// Событие таймера: системное уведомление + опционально поднять окно
  /// + опционально в Telegram.
  Future<void> event(
    AppSettings settings, {
    required String title,
    required String body,
    bool raise = false,
  }) async {
    if (settings.notifications) {
      await show(title, body);
    }
    if (raise && settings.popupRaiseWindow) {
      await windowManager.show();
      await windowManager.focus();
    }
    if (settings.notifyTelegram &&
        settings.telegramToken.isNotEmpty &&
        settings.telegramChatId.isNotEmpty) {
      await _telegram(settings, '$title · $body');
    }
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    final notification = LocalNotification(title: title, body: body);
    await notification.show();
  }

  Future<void> _telegram(AppSettings settings, String text) async {
    try {
      // Жёсткий таймаут: недоступный Telegram не должен подвешивать
      // цепочку завершения помидора (журнал/статистика ждут event()).
      await () async {
        final request = await _http.postUrl(
          Uri.https(
            'api.telegram.org',
            '/bot${settings.telegramToken}/sendMessage',
          ),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({'chat_id': settings.telegramChatId, 'text': text}),
        );
        final response = await request.close();
        await response.drain<void>();
      }().timeout(const Duration(seconds: 10));
    } on Exception {
      // Telegram недоступен — уведомление уже показано локально.
    }
  }
}
