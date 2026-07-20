import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as gd;
import 'package:http/http.dart' as http;

import '../data/data_merge.dart';
import 'sync_auth.dart';

/// Итог одного прохода синка (для статуса в UI).
enum SyncOutcome { notConnected, busy, noChanges, pushed, pulled, merged }

/// Метаданные удалённого файла.
class RemoteFileInfo {
  const RemoteFileInfo({required this.id, this.revision, this.modified});

  final String id;
  final String? revision;
  final DateTime? modified;
}

/// Удалённое хранилище одного файла. Обёртка над Drive, в тестах — память.
abstract class RemoteStore {
  Future<RemoteFileInfo?> find(String name);
  Future<RemoteFileInfo> create(String name, List<int> bytes);
  Future<RemoteFileInfo> update(String id, List<int> bytes);
  Future<String> download(String id);
}

/// Drive v3, файлы в appDataFolder.
class DriveRemoteStore implements RemoteStore {
  DriveRemoteStore(http.Client client) : _api = gd.DriveApi(client);

  final gd.DriveApi _api;

  static RemoteFileInfo _info(gd.File f) => RemoteFileInfo(
    id: f.id!,
    revision: f.headRevisionId,
    modified: f.modifiedTime,
  );

  @override
  Future<RemoteFileInfo?> find(String name) async {
    final res = await _api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name'",
      $fields: 'files(id,name,modifiedTime,headRevisionId)',
      pageSize: 10,
    );
    final files = res.files;
    if (files == null || files.isEmpty) return null;
    return _info(files.first);
  }

  @override
  Future<RemoteFileInfo> create(String name, List<int> bytes) async {
    final created = await _api.files.create(
      gd.File(name: name, parents: ['appDataFolder']),
      uploadMedia: gd.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      ),
      $fields: 'id,headRevisionId,modifiedTime',
    );
    return _info(created);
  }

  @override
  Future<RemoteFileInfo> update(String id, List<int> bytes) async {
    // В update тело File пустое: parents в Drive v3 не переписываются.
    final updated = await _api.files.update(
      gd.File(),
      id,
      uploadMedia: gd.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      ),
      $fields: 'id,headRevisionId,modifiedTime',
    );
    return _info(updated);
  }

  @override
  Future<String> download(String id) async {
    final media =
        await _api.files.get(id, downloadOptions: gd.DownloadOptions.fullMedia)
            as gd.Media;
    return media.stream.transform(utf8.decoder).join();
  }
}

class _SyncMeta {
  const _SyncMeta({this.rev, this.dirty = false, this.lastSync});

  final String? rev;
  final bool dirty;
  final DateTime? lastSync;

  _SyncMeta copy({String? rev, bool? dirty, DateTime? lastSync}) => _SyncMeta(
    rev: rev ?? this.rev,
    dirty: dirty ?? this.dirty,
    lastSync: lastSync ?? this.lastSync,
  );

  Map<String, dynamic> toJson() => {
    'rev': rev,
    'dirty': dirty,
    if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
  };

  static _SyncMeta fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const _SyncMeta();
    return _SyncMeta(
      rev: json['rev'] as String?,
      dirty: json['dirty'] == true,
      lastSync: json['lastSync'] is String
          ? DateTime.tryParse(json['lastSync'] as String)
          : null,
    );
  }
}

/// Синк data.json с Google Drive appDataFolder — задачи, журнал и спринты
/// одним документом.
///
/// Конфликт (менялись оба устройства) разрешается слиянием, а не выбором
/// победителя: списки объединяются по id, надгробия хоронят удалённое.
/// Время правки решает только судьбу спорных скаляров — цели дня и вехи
/// недели; проигравшая версия на всякий случай ложится в data_conflict.json.
class DriveSyncService {
  DriveSyncService({
    required this.auth,
    required this.localFile,
    required this.applyRemote,
    required this.onRemoteApplied,
    RemoteStore Function(http.Client client)? storeFactory,
  }) : _storeFactory = storeFactory ?? DriveRemoteStore.new;

  static const remoteName = 'data.json';

  final SyncAuth auth;
  final Future<File> Function() localFile;

  /// Записать пришедшую версию. Делает это репозиторий, а не синк: документ
  /// в памяти и файл на диске обязаны меняться вместе.
  final Future<void> Function(String content) applyRemote;

  /// Данные заменены удалённой версией — перечитать стейт.
  final Future<void> Function() onRemoteApplied;
  final RemoteStore Function(http.Client) _storeFactory;

  _SyncMeta? _meta;
  int _dirtyEpoch = 0;
  bool _running = false;

  Future<File> _metaFile() async =>
      File('${(await localFile()).path}.sync.json');

  Future<_SyncMeta> _loadMeta() async {
    final cached = _meta;
    if (cached != null) return cached;
    try {
      final file = await _metaFile();
      if (!await file.exists()) return _meta = const _SyncMeta();
      return _meta = _SyncMeta.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return _meta = const _SyncMeta();
    }
  }

  Future<void> _saveMeta(_SyncMeta meta) async {
    _meta = meta;
    try {
      final file = await _metaFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(meta.toJson()));
    } on FileSystemException {
      // Потеря меты не критична: худшее — лишний merge при следующем синке.
    }
  }

  bool get dirty => _meta?.dirty ?? false;

  Future<DateTime?> storedLastSync() async => (await _loadMeta()).lastSync;

  /// Локальные данные изменились: пометить до того, как уедет пуш.
  Future<void> markDirty() async {
    _dirtyEpoch++;
    await _saveMeta((await _loadMeta()).copy(dirty: true));
  }

  /// Выход из аккаунта. Мету сбрасываем: повторное подключение пройдёт
  /// через merge по id, ничего не потеряется.
  Future<void> signOut() async {
    await auth.signOut();
    await _saveMeta(const _SyncMeta(dirty: true));
  }

  Future<SyncOutcome> sync({bool interactive = false}) async {
    if (_running) return SyncOutcome.busy;
    _running = true;
    try {
      // Интерактив идёт сразу в signIn: на Android «тихое» restore() само
      // показывает системный диалог, и при его неудаче пользователь видел
      // окно входа дважды подряд. Нажали «Подключить» — значит вход нужен.
      final client = interactive ? await auth.signIn() : await auth.restore();
      if (client == null) return SyncOutcome.notConnected;

      final store = _storeFactory(client);
      final meta = await _loadMeta();
      final local = await localFile();
      // Эпоха снимается ДО чтения файла: правка, прилетевшая между чтением
      // и пушем, иначе уехала бы незамеченной (пушим старые байты, а dirty
      // при этом сбрасываем) и не уехала бы уже никогда.
      final epoch = _dirtyEpoch;
      final localBytes = await local.exists()
          ? await local.readAsBytes()
          : null;
      final remote = await store.find(remoteName);
      final now = DateTime.now();

      // В Drive ещё пусто — просто отдать своё.
      if (remote == null) {
        if (localBytes == null) {
          await _saveMeta(meta.copy(lastSync: now));
          return SyncOutcome.noChanges;
        }
        final info = await store.create(remoteName, localBytes);
        await _finish(info.revision, epoch, now);
        return SyncOutcome.pushed;
      }

      // Это устройство ещё не синкалось, а в Drive файл уже есть:
      // объединяем и кладём результат в обе стороны.
      if (meta.rev == null) {
        final remoteJson = await store.download(remote.id);
        if (_dirtyEpoch != epoch) return SyncOutcome.busy;
        final merged = mergeData(
          localBytes == null ? null : utf8.decode(localBytes),
          remoteJson,
          localWins: true,
        );
        await applyRemote(merged);
        final info = await store.update(remote.id, utf8.encode(merged));
        await _finish(info.revision, epoch, now);
        await onRemoteApplied();
        return SyncOutcome.merged;
      }

      // Drive не менялся с прошлого синка.
      if (remote.revision == meta.rev) {
        if (!meta.dirty || localBytes == null) {
          await _saveMeta((await _loadMeta()).copy(lastSync: now));
          return SyncOutcome.noChanges;
        }
        final info = await store.update(remote.id, localBytes);
        await _finish(info.revision, epoch, now);
        return SyncOutcome.pushed;
      }

      // Drive менялся. Локальных правок нет — забираем удалённое.
      // Всё равно через слияние: забытый где-нибудь markDirty тогда просто
      // не сможет стать причиной потери данных.
      if (!meta.dirty || localBytes == null) {
        final remoteJson = await store.download(remote.id);
        // Правка успела прилететь, пока качали: не затираем свежее стейлом —
        // следующий синк разрулит это как обычный конфликт (dirty уже стоит).
        if (_dirtyEpoch != epoch) return SyncOutcome.busy;
        await applyRemote(
          mergeData(
            localBytes == null ? null : utf8.decode(localBytes),
            remoteJson,
            localWins: false,
          ),
        );
        await _finish(remote.revision, epoch, now);
        await onRemoteApplied();
        return SyncOutcome.pulled;
      }

      // Конфликт: менялись оба. Сливаем, ничего не выбрасывая; более свежая
      // сторона решает только спорные скаляры. Проигравшая версия — в бэкап.
      final remoteJson = await store.download(remote.id);
      if (_dirtyEpoch != epoch) return SyncOutcome.busy;
      final localTime = await local.lastModified();
      final remoteTime =
          remote.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
      final localWins = localTime.isAfter(remoteTime);
      await _backup(local, localWins ? remoteJson : utf8.decode(localBytes));
      final merged = mergeData(
        utf8.decode(localBytes),
        remoteJson,
        localWins: localWins,
      );
      await applyRemote(merged);
      final info = await store.update(remote.id, utf8.encode(merged));
      await _finish(info.revision, epoch, now);
      await onRemoteApplied();
      return SyncOutcome.merged;
    } finally {
      _running = false;
    }
  }

  /// Синк завершён. dirty сбрасываем только если за время аплоада не было
  /// новых локальных правок — иначе их пуш молча бы потерялся.
  Future<void> _finish(String? revision, int epoch, DateTime now) async {
    final fresh = await _loadMeta();
    await _saveMeta(
      _SyncMeta(
        rev: revision,
        dirty: fresh.dirty && _dirtyEpoch != epoch,
        lastSync: now,
      ),
    );
  }

  /// Проигравшая сторона конфликта — рядом, в data_conflict.json.
  Future<void> _backup(File local, String content) async {
    final file = File(
      '${local.parent.path}${Platform.pathSeparator}data_conflict.json',
    );
    await file.writeAsString(content, flush: true);
  }
}
