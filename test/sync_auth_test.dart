import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/services/sync_auth.dart';

/// Инициализацию google_sign_in в тестах не дёрнуть (платформенный канал),
/// поэтому проверяем ровно те решения, что принимаются ДО неё: когда вообще
/// инициализироваться, а когда честно сказать, чего не хватает.
void main() {
  test('пустой Server Client ID — понятная ошибка, а не падение плагина',
      () async {
    final auth = MobileSyncAuth(serverClientId: () => '   ');
    await expectLater(
      auth.signIn(),
      throwsA(isA<SyncConfigException>()),
    );
  });

  test('пустой Server Client ID: restore молчит, а не шумит ошибкой',
      () async {
    final auth = MobileSyncAuth(serverClientId: () => '');
    // Стартовый тихий синк не должен пугать пользователя красным текстом.
    expect(await auth.restore(), isNull);
  });

  test('без инициализации signOut — no-op, не трогает плагин', () async {
    final auth = MobileSyncAuth(serverClientId: () => '');
    await auth.signOut();
  });

  test('SyncConfigException печатается без префикса Exception', () {
    expect(const SyncConfigException('заполни поле').toString(), 'заполни поле');
  });
}
