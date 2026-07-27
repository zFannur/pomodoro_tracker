import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';

import '../core/failure.dart';
import '../domain/entities/app_settings.dart';
import '../domain/repositories.dart';
import 'markdown_codec.dart';

/// Доступ к папке хранилища. Корень меняется из настроек на лету.
class VaultStore {
  VaultStore(this.root);

  String root;

  static const tasksFileName = 'Задачи.md';
  static const journalDirName = 'Журнал';
  static const sprintsDirName = 'Спринты';

  File tasksFile() => File('$root${Platform.pathSeparator}$tasksFileName');

  File journalFile(DateTime d) => File(
    '$root${Platform.pathSeparator}$journalDirName'
    '${Platform.pathSeparator}${d.year}-${two(d.month)}'
    '${Platform.pathSeparator}${dateKey(d)}.md',
  );

  Directory sprintsDir() =>
      Directory('$root${Platform.pathSeparator}$sprintsDirName');

  File sprintFile(String id) =>
      File('${sprintsDir().path}${Platform.pathSeparator}$id.md');

  Future<String?> read(File file) async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> write(File file, String content) async {
    await file.parent.create(recursive: true);
    // Атомарно: temp + rename, чтобы Obsidian/Drive не видели полфайла.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }
}

/// Файл-инбокс «Входящие.md» в валте: ручной захват задач из Obsidian
/// (или с телефона через Drive). Направление строго одно — файл → приложение:
/// приложение забирает строки и возвращает файл к шаблону, мерджить нечего.
class InboxImporter {
  InboxImporter(this._store);

  final VaultStore _store;

  static const fileName = 'Входящие.md';
  static const template =
      '# Входящие\n\n'
      '<!-- Строки отсюда Помодоро Трекер забирает во «Входящие» '
      'при запуске и фокусе окна. Формат: #категория описание ~помидоры -->\n\n'
      '- \n';

  File _file() => File('${_store.root}${Platform.pathSeparator}$fileName');

  /// Забрать строки-задачи и вернуть файл к шаблону.
  /// Ошибки ФС (валт недоступен) — пустой список, приложение живёт дальше.
  Future<List<String>> drain() async {
    try {
      final file = _file();
      final content = await _store.read(file);
      if (content == null) {
        // Создаём точку входа, чтобы файл был заметен в валте.
        await _store.write(file, template);
        return const [];
      }
      final lines = <String>[];
      for (final raw in content.split('\n')) {
        var line = raw.trim();
        // Заголовок — только «# » с пробелом: строка «#категория описание»
        // (smart-ввод) заголовком не является и должна попасть в задачи.
        if (line.isEmpty ||
            RegExp(r'^#{1,6}\s').hasMatch(line) ||
            line.startsWith('<!--')) {
          continue;
        }
        // Срезаем маркеры списка и чекбоксы: «- », «- [ ] », «* ».
        line = line.replaceFirst(RegExp(r'^[-*]\s*(\[.\]\s*)?'), '').trim();
        if (line.isEmpty) continue;
        lines.add(line);
      }
      if (lines.isNotEmpty) await _store.write(file, template);
      return lines;
    } on FileSystemException {
      return const [];
    }
  }
}

class SettingsRepositoryImpl implements SettingsRepository {
  File? _file;

  Future<File> _settingsFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}settings.json');
    _file = file;
    return file;
  }

  /// На мобильных задаётся из main(): документы приложения.
  static String? mobileRoot;

  static String defaultStoragePath() {
    final mobile = mobileRoot;
    if (mobile != null) {
      return '$mobile${Platform.pathSeparator}Помодоро';
    }
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      final vault = Directory(
        '$profile${Platform.pathSeparator}Мой диск'
        '${Platform.pathSeparator}Obsidian',
      );
      if (vault.existsSync()) {
        return '${vault.path}${Platform.pathSeparator}Помодоро';
      }
      return '$profile${Platform.pathSeparator}Documents'
          '${Platform.pathSeparator}Помодоро';
    }
    return 'Помодоро';
  }

  @override
  Future<Either<Failure, AppSettings>> load() async {
    try {
      final file = await _settingsFile();
      final fallback = defaultStoragePath();
      if (!await file.exists()) {
        return Either.right(
          AppSettings.fromJson(const {}, fallbackPath: fallback),
        );
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) {
        return Either.right(
          AppSettings.fromJson(const {}, fallbackPath: fallback),
        );
      }
      return Either.right(AppSettings.fromJson(json, fallbackPath: fallback));
    } on FileSystemException catch (e) {
      return Either.left(
        StorageFailure('Не удалось прочитать настройки: ${e.message}'),
      );
    } on FormatException {
      // Битый JSON — стартуем с настроек по умолчанию, не блокируя запуск.
      return Either.right(
        AppSettings.fromJson(const {}, fallbackPath: defaultStoragePath()),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> save(AppSettings settings) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      // Атомарно: обрыв процесса на полуслове оставлял обрезанный JSON, а
      // load() молча подменял ВСЕ настройки дефолтами — включая ключи синка,
      // после чего синк тихо переставал работать.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
        flush: true,
      );
      await tmp.rename(file.path);
      return Either.right(unit);
    } on FileSystemException catch (e) {
      return Either.left(
        StorageFailure('Не удалось сохранить настройки: ${e.message}'),
      );
    }
  }
}
