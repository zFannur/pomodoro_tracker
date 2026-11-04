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

/// Отрезок активности в одном окне (в помидоре или вне его — зависит от
/// того, в каком ряду лежит).
class ActivitySegment {
  ActivitySegment({
    required this.from,
    required this.to,
    required this.app,
    this.title = '',
  });

  final DateTime from;
  DateTime to;
  final String app;
  final String title;

  Map<String, dynamic> toJson() => {
    'from': from.toIso8601String(),
    'to': to.toIso8601String(),
    'app': app,
    'title': title,
  };

  static ActivitySegment? fromJson(Object? json) {
    if (json is! Map) return null;
    final app = json['app'];
    if (app is! String || app.isEmpty) return null;
    final fromStr = json['from'];
    final toStr = json['to'];
    if (fromStr is! String || toStr is! String) return null;
    final from = DateTime.tryParse(fromStr);
    final to = DateTime.tryParse(toStr);
    if (from == null || to == null) return null;
    return ActivitySegment(
      from: from,
      to: to,
      app: app,
      title: json['title'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivitySegment &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to &&
          app == other.app &&
          title == other.title;

  @override
  int get hashCode => Object.hash(from, to, app, title);
}

/// Все данные трекера: день «yyyy-MM-dd» → агрегаты дня, отрезки помидоров,
/// отрезки вне помидоров и множество «отвлекающих» ключей.
class ActivityData {
  final Map<String, Map<String, ActivityEntry>> days = {};
  final Map<String, List<ActivitySegment>> focusSegments = {};

  /// Отрезки вне помидоров («что было вместо»): самый объёмный ряд,
  /// поэтому хранится короче основных данных.
  final Map<String, List<ActivitySegment>> idleSegments = {};
  final Set<String> distracting = {};

  static Map<String, dynamic> _segmentsJson(
    Map<String, List<ActivitySegment>> byDay,
  ) => {
    for (final day in byDay.entries)
      if (day.value.isNotEmpty) day.key: [for (final s in day.value) s.toJson()],
  };

  Map<String, dynamic> toJson() {
    final idle = _segmentsJson(idleSegments);
    return {
      for (final day in days.entries)
        if (day.value.isNotEmpty)
          day.key: [for (final e in day.value.values) e.toJson()],
      _segmentsKey: _segmentsJson(focusSegments),
      if (idle.isNotEmpty) _idleKey: idle,
      _distractingKey: distracting.toList()..sort(),
    };
  }

  /// Словарь «день → отрезки» из JSON; битые отрезки и дни пропускаются.
  static void _readSegments(
    Object? raw,
    Map<String, List<ActivitySegment>> into,
  ) {
    if (raw is! Map) return;
    for (final segEntry in raw.entries) {
      final segKey = segEntry.key;
      if (segKey is! String) continue;
      final segList = segEntry.value;
      if (segList is! List) continue;
      final list = <ActivitySegment>[];
      for (final raw in segList) {
        final segment = ActivitySegment.fromJson(raw);
        if (segment != null) list.add(segment);
      }
      if (list.isNotEmpty) into[segKey] = list;
    }
  }

  static ActivityData fromJson(Object? json) {
    final data = ActivityData();
    if (json is! Map) return data;
    for (final item in json.entries) {
      if (item.key == _distractingKey) {
        final value = item.value;
        if (value is List) {
          data.distracting.addAll(value.whereType<String>());
        }
        continue;
      }
      if (item.key == _segmentsKey) {
        _readSegments(item.value, data.focusSegments);
        continue;
      }
      // Служебный ключ, не день: без этой ветки его спасало бы только то,
      // что значение — словарь, а не список.
      if (item.key == _idleKey) {
        _readSegments(item.value, data.idleSegments);
        continue;
      }
      final value = item.value;
      if (value is! List) continue;
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

/// Ключ словаря отрезков помидоров в activity.json.
const _segmentsKey = 'segments';

/// Ключ словаря отрезков вне помидоров. Старые версии приложения его
/// пропускают: значение — словарь, а днём считается только список.
const _idleKey = 'idle';

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
