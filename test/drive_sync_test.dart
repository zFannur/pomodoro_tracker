import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pomodoro_tracker/services/drive_sync_service.dart';
import 'package:pomodoro_tracker/services/sync_auth.dart';

class _FakeAuth implements SyncAuth {
  bool connected = true;
  int restores = 0;
  int signIns = 0;

  @override
  Future<http.Client?> restore() async {
    restores++;
    return connected ? http.Client() : null;
  }

  @override
  Future<http.Client?> signIn() async {
    signIns++;
    return http.Client();
  }

  @override
  Future<void> signOut() async => connected = false;
}

/// Drive в памяти: один файл, ревизия растёт на каждой записи.
class _FakeRemote implements RemoteStore {
  String? content;
  int rev = 0;
  DateTime modified = DateTime(2026, 1, 1);
  Future<void> Function()? onUpload;

  Future<void> Function()? onDownload;
  Future<void> Function()? onFind;

  RemoteFileInfo get _info =>
      RemoteFileInfo(id: 'f1', revision: '$rev', modified: modified);

  /// Правка «с другого устройства».
  void external(String json, {DateTime? at}) {
    content = json;
    rev++;
    if (at != null) modified = at;
  }

  @override
  Future<RemoteFileInfo?> find(String name) async {
    await onFind?.call();
    return content == null ? null : _info;
  }

  @override
  Future<RemoteFileInfo> create(String name, List<int> bytes) =>
      update('f1', bytes);

  @override
  Future<RemoteFileInfo> update(String id, List<int> bytes) async {
    await onUpload?.call();
    content = utf8.decode(bytes);
    rev++;
    return _info;
  }

  @override
  Future<String> download(String id) async {
    await onDownload?.call();
    return content!;
  }
}

String tasksJson(List<String> ids) => jsonEncode({
  'schema': 1,
  'todo': [
    for (final id in ids) {'id': id, 'desc': id, 'cat': 'x', 'min': 25},
  ],
  'planner': <Object>[],
});

List<String> idsOf(String json) => [
  for (final t in (jsonDecode(json) as Map<String, dynamic>)['todo'] as List)
    (t as Map<String, dynamic>)['id'] as String,
];

void main() {
  late Directory dir;
  late File local;
  late _FakeRemote remote;
  late _FakeAuth auth;
  late DriveSyncService service;
  var applied = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('drive_sync_test');
    local = File('${dir.path}${Platform.pathSeparator}data.json');
    remote = _FakeRemote();
    auth = _FakeAuth();
    applied = 0;
    service = DriveSyncService(
      auth: auth,
      localFile: () async => local,
      // В приложении файл пишет репозиторий; здесь достаточно записать.
      applyRemote: (content) => local.writeAsString(content, flush: true),
      onRemoteApplied: () async => applied++,
      storeFactory: (_) => remote,
    );
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('не подключены — notConnected, без интерактива', () async {
    auth.connected = false;
    expect(await service.sync(), SyncOutcome.notConnected);
  });

  test('«Подключить» зовёт вход один раз, без тихого restore', () async {
    // На Android restore() сам показывает системный диалог — при цепочке
    // restore→signIn пользователь видел окно входа дважды подряд.
    auth.connected = false;
    await local.writeAsString(tasksJson(['a']));
    expect(await service.sync(interactive: true), SyncOutcome.pushed);
    expect(auth.signIns, 1);
    expect(auth.restores, 0);
  });

  test('первый синк отдаёт локальное, повторный — noChanges', () async {
    await local.writeAsString(tasksJson(['a']));
    expect(await service.sync(), SyncOutcome.pushed);
    expect(idsOf(remote.content!), ['a']);
    expect(await service.sync(), SyncOutcome.noChanges);
  });

  test('правка с другого устройства подтягивается (pull)', () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    remote.external(tasksJson(['a', 'b']));
    expect(await service.sync(), SyncOutcome.pulled);
    expect(idsOf(await local.readAsString()), ['a', 'b']);
    expect(applied, 1);
  });

  test('локальная правка уезжает (push) после markDirty', () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    await local.writeAsString(tasksJson(['a', 'c']));
    await service.markDirty();
    expect(await service.sync(), SyncOutcome.pushed);
    expect(idsOf(remote.content!), ['a', 'c']);
  });

  test('первое подключение при непустом Drive — merge по id', () async {
    remote.external(tasksJson(['b']));
    await local.writeAsString(tasksJson(['a']));
    expect(await service.sync(), SyncOutcome.merged);
    expect(idsOf(await local.readAsString()).toSet(), {'a', 'b'});
    expect(idsOf(remote.content!).toSet(), {'a', 'b'});
    expect(applied, 1);
  });

  test('конфликт: обе стороны выживают, проигравшая — ещё и в бэкап',
      () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    remote.external(tasksJson(['remote']), at: DateTime(2026, 1, 2));
    await local.writeAsString(tasksJson(['local']));
    await service.markDirty();
    // Файл только что записан — mtime заведомо новее 2026-01-02.
    expect(await service.sync(), SyncOutcome.merged);
    // Раньше здесь побеждала одна сторона, а вторая молча пропадала.
    expect(idsOf(remote.content!).toSet(), {'local', 'remote'});
    expect(idsOf(await local.readAsString()).toSet(), {'local', 'remote'});
    final backup = File(
      '${dir.path}${Platform.pathSeparator}data_conflict.json',
    );
    expect(idsOf(await backup.readAsString()), ['remote']);
    expect(applied, 1);
  });

  test('конфликт с более свежим удалённым: бэкап — локальная версия',
      () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    remote.external(
      tasksJson(['remote']),
      at: DateTime.now().add(const Duration(days: 1)),
    );
    await local.writeAsString(tasksJson(['local']));
    await service.markDirty();
    expect(await service.sync(), SyncOutcome.merged);
    expect(idsOf(await local.readAsString()).toSet(), {'local', 'remote'});
    final backup = File(
      '${dir.path}${Platform.pathSeparator}data_conflict.json',
    );
    expect(idsOf(await backup.readAsString()), ['local']);
    expect(applied, 1);
  });

  test('правка во время аплоада не теряет dirty-флаг', () async {
    await local.writeAsString(tasksJson(['a']));
    remote.onUpload = () async {
      await service.markDirty();
    };
    await service.sync();
    // dirty выжил: следующий синк снова отправит данные.
    expect(service.dirty, isTrue);
    remote.onUpload = null;
    expect(await service.sync(), SyncOutcome.pushed);
    expect(service.dirty, isFalse);
  });

  test('правка во время скачивания прерывает pull — свежее не затирается',
      () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    remote.external(tasksJson(['b']));
    remote.onDownload = () async {
      await local.writeAsString(tasksJson(['fresh']));
      await service.markDirty();
    };
    expect(await service.sync(), SyncOutcome.busy);
    expect(idsOf(await local.readAsString()), ['fresh']);
    // Следующий синк разрешает это как конфликт — и сохраняет обе стороны.
    remote.onDownload = null;
    expect(await service.sync(), SyncOutcome.merged);
    expect(idsOf(remote.content!).toSet(), {'fresh', 'b'});
  });

  test('правка во время сетевого find не теряется: dirty выживает', () async {
    await local.writeAsString(tasksJson(['a']));
    await service.sync();
    await local.writeAsString(tasksJson(['a', 'b']));
    await service.markDirty();
    // Пока идёт find, прилетает ещё одна правка: пуш уедет со старыми
    // байтами (их уже прочли), но dirty обязан пережить синк.
    remote.onFind = () async {
      remote.onFind = null;
      await local.writeAsString(tasksJson(['a', 'b', 'c']));
      await service.markDirty();
    };
    expect(await service.sync(), SyncOutcome.pushed);
    expect(idsOf(remote.content!), ['a', 'b']);
    expect(service.dirty, isTrue);
    // Именно этот синк и довозит потерянную правку.
    expect(await service.sync(), SyncOutcome.pushed);
    expect(idsOf(remote.content!), ['a', 'b', 'c']);
  });

}
