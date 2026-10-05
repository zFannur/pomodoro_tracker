import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Запись дня: сколько секунд провели в приложении (для браузеров — во
/// вкладке с этим заголовком) и сколько из них шёл помидор.
class ActivityEntry {
  ActivityEntry({
    required this.app,
    this.title = '',
    this.seconds = 0,
    this.focusSeconds = 0,
  });

  /// Имя exe без пути: `chrome.exe`.
  final String app;

  /// Название вкладки — только у браузеров, у остальных пусто.
  final String title;
  int seconds;
  int focusSeconds;

  /// Ключ классификации «отвлекающее»: вкладка браузера или exe.
  String get key => title.isEmpty ? app : title;

  Map<String, dynamic> toJson() => {
    'app': app,
    'title': title,
    'seconds': seconds,
    'focusSeconds': focusSeconds,
  };

  static ActivityEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final app = json['app'];
    if (app is! String || app.isEmpty) return null;
    return ActivityEntry(
      app: app,
      title: json['title'] as String? ?? '',
      seconds: json['seconds'] as int? ?? 0,
      focusSeconds: json['focusSeconds'] as int? ?? 0,
    );
  }
}

/// Все данные трекера: день «yyyy-MM-dd» → записи (ключ `app|title`) и
/// множество «отвлекающих» ключей.
class ActivityData {
  final Map<String, Map<String, ActivityEntry>> days = {};
  final Set<String> distracting = {};

  Map<String, dynamic> toJson() => {
    for (final day in days.entries)
      if (day.value.isNotEmpty)
        day.key: [for (final e in day.value.values) e.toJson()],
    _distractingKey: distracting.toList()..sort(),
  };

  static ActivityData fromJson(Object? json) {
    final data = ActivityData();
    if (json is! Map<String, dynamic>) return data;
    for (final item in json.entries) {
      final value = item.value;
      if (value is! List) continue;
      if (item.key == _distractingKey) {
        data.distracting.addAll(value.whereType<String>());
        continue;
      }
      final day = <String, ActivityEntry>{};
      for (final raw in value) {
        final entry = ActivityEntry.fromJson(raw);
        if (entry != null) day['${entry.app}|${entry.title}'] = entry;
      }
      data.days[item.key] = day;
    }
    return data;
  }
}

/// Ключ списка «отвлекающих» среди ключей-дат в activity.json.
const _distractingKey = 'distracting';

/// JSON-файл активности в AppData (локальные данные машины, в синк не едет).
class ActivityStore {
  File? _file;

  Future<File> _activityFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}activity.json');
    _file = file;
    return file;
  }

  Future<ActivityData> load() async {
    try {
      final file = await _activityFile();
      if (!await file.exists()) return ActivityData();
      return ActivityData.fromJson(jsonDecode(await file.readAsString()));
    } on FileSystemException {
      return ActivityData();
    } on FormatException {
      return ActivityData();
    }
  }

  Future<void> save(ActivityData data) async {
    // JSON собираем до первого await: таймер трекера продолжает дописывать
    // в те же карты, пока идёт запись на диск.
    final json = jsonEncode(data.toJson());
    try {
      final file = await _activityFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      // Потеря минуты статистики не критична — молча пропускаем.
    }
  }
}
