import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gd;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/strings.dart';

/// Скоуп только appDataFolder: приложение не видит остальной Drive.
const kDriveScopes = [gd.DriveApi.driveAppdataScope];

/// Синк настроен неверно (не Error: SyncCubit ловит именно Exception,
/// и текст показывается пользователю как есть — без префикса «Exception:»).
class SyncConfigException implements Exception {
  const SyncConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Авторизация Google по платформам: готовый http-клиент с токеном
/// или null, если сессии нет и интерактив не разрешён/не удался.
abstract class SyncAuth {
  factory SyncAuth({
    required String Function() clientId,
    required String Function() clientSecret,
    required String Function() serverClientId,
  }) => Platform.isWindows
      ? WindowsSyncAuth(clientId: clientId, clientSecret: clientSecret)
      : MobileSyncAuth(serverClientId: serverClientId);

  /// Тихое восстановление сессии, без UI.
  Future<http.Client?> restore();

  /// Интерактивный вход: браузер (Windows) или системный диалог (Android).
  Future<http.Client?> signIn();

  Future<void> signOut();
}

/// Windows: OAuth loopback-консент через системный браузер
/// (google_sign_in Windows не поддерживает). Client ID типа «Desktop app»;
/// его secret по политике Google секретом не считается.
class WindowsSyncAuth implements SyncAuth {
  WindowsSyncAuth({required this.clientId, required this.clientSecret});

  final String Function() clientId;
  final String Function() clientSecret;
  AutoRefreshingAuthClient? _client;

  Future<File> _credsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}gdrive_credentials.json');
  }

  ClientId? _id() {
    final id = clientId().trim();
    final secret = clientSecret().trim();
    if (id.isEmpty || secret.isEmpty) return null;
    return ClientId(id, secret);
  }

  @override
  Future<http.Client?> restore() async {
    final cached = _client;
    if (cached != null) return cached;
    final id = _id();
    if (id == null) return null;
    try {
      final file = await _credsFile();
      if (!await file.exists()) return null;
      final saved = AccessCredentials.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      final refresh = saved.refreshToken;
      if (refresh == null) return null;
      final client = await clientViaRefreshToken(id, refresh, kDriveScopes);
      _remember(client);
      return client;
    } on Exception {
      // Битые/отозванные креды — считаем, что не подключены.
      return null;
    }
  }

  @override
  Future<http.Client?> signIn() async {
    final id = _id();
    if (id == null) return null;
    final client = await clientViaUserConsent(
      id,
      kDriveScopes,
      (url) async {
        if (!await launchUrl(Uri.parse(url))) {
          throw Exception('Не удалось открыть браузер для входа Google');
        }
      },
      customPostAuthPage:
          '<html><meta charset="utf-8">'
          '<body style="font-family:sans-serif;text-align:center">'
          '<h2>Готово — вкладку можно закрыть.</h2></body></html>',
    );
    _remember(client);
    await _persist(client.credentials);
    return client;
  }

  void _remember(AutoRefreshingAuthClient client) {
    _client = client;
    // Авторефреш меняет access token — пересохраняем, чтобы пережить рестарт.
    client.credentialUpdates.listen(_persist, onError: (_) {});
  }

  Future<void> _persist(AccessCredentials credentials) async {
    final file = await _credsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(credentials.toJson()));
  }

  @override
  Future<void> signOut() async {
    _client?.close();
    _client = null;
    final file = await _credsFile();
    if (await file.exists()) await file.delete();
  }
}

/// Android/iOS: google_sign_in 7.x. Нужен OAuth-клиент типа Android
/// (package + SHA-1) в том же Cloud-проекте и serverClientId типа Web.
class MobileSyncAuth implements SyncAuth {
  MobileSyncAuth({required this.serverClientId});

  final String Function() serverClientId;
  Future<void>? _init;
  String? _initedWith;

  /// Кешируем АККАУНТ, а не http.Client. Клиент из
  /// extension_google_sign_in_as_googleapis_auth строится без refresh-токена и
  /// с выдуманным сроком «сейчас + 365 дней»: закешированный, он через час
  /// начал бы молча отдавать 401, и googleapis_auth даже не заметил бы этого.
  /// Аккаунт же переиспользуется без похода в системный UI.
  GoogleSignInAccount? _account;

  /// initialize() по контракту пакета допустим ровно один раз за процесс —
  /// повторный вызов реально ломает плагин. Поэтому единственный вызов
  /// делаем сразу с настоящим serverClientId: пока поле пусто (например,
  /// после переустановки), не инициализируемся вовсе, иначе зафиксировали бы
  /// пустую конфигурацию и введённый следом ID заработал бы лишь после
  /// перезапуска.
  Future<void> _ensureInit() async {
    final server = serverClientId().trim();
    final cached = _init;
    if (cached != null) {
      await cached;
      // Конфигурацию на лету не переиграть — честно просим перезапуск.
      if (_initedWith != server) {
        throw SyncConfigException(S.syncRestartNeeded);
      }
      return;
    }
    if (server.isEmpty) throw SyncConfigException(S.syncFillServerClientId);
    _initedWith = server;
    final future = GoogleSignIn.instance.initialize(serverClientId: server);
    _init = future;
    try {
      await future;
    } on Object {
      // Провалившуюся инициализацию не кешируем: иначе одна ошибка отравляет
      // все следующие попытки до перезапуска приложения.
      _init = null;
      _initedWith = null;
      rethrow;
    }
  }

  @override
  Future<http.Client?> restore() async {
    // Тихий путь: не настроено — просто «не подключено», без ошибки.
    if (_init == null && serverClientId().trim().isEmpty) return null;
    await _ensureInit();
    // Без кеша каждый проход синка снова дёргал Credential Manager, а он на
    // Android рисует системную шторку — она и выглядела как «авторизация
    // просится по кругу».
    final account =
        _account ??
        await (GoogleSignIn.instance.attemptLightweightAuthentication() ??
            Future<GoogleSignInAccount?>.value());
    if (account == null) return null;
    _account = account;
    final authz = await account.authorizationClient.authorizationForScopes(
      kDriveScopes,
    );
    if (authz == null) {
      // Разрешение отозвали — аккаунт из кеша убираем, иначе следующий проход
      // будет бесконечно строить клиента на мёртвой авторизации.
      _account = null;
      return null;
    }
    return authz.authClient(scopes: kDriveScopes);
  }

  @override
  Future<http.Client?> signIn() async {
    await _ensureInit();
    final account = await GoogleSignIn.instance.authenticate();
    _account = account;
    final authz = await account.authorizationClient.authorizeScopes(
      kDriveScopes,
    );
    return authz.authClient(scopes: kDriveScopes);
  }

  @override
  Future<void> signOut() async {
    _account = null;
    // Не инициализировались — и выходить неоткуда.
    if (_init == null) return;
    await _ensureInit();
    await GoogleSignIn.instance.signOut();
  }
}
