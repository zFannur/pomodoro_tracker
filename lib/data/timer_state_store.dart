import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Снимок состояния таймера для восстановления после перезапуска.
class TimerSnapshot {
  const TimerSnapshot({
    required this.mode,
    required this.run,
    required this.remaining,
    required this.total,
    required this.series,
    required this.interruptions,
    required this.delaysMs,
    required this.savedAt,
  });

  final String mode;
  final String run;
  final int remaining;
  final int total;
  final int series;
  final int interruptions;
  final int delaysMs;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'run': run,
    'remaining': remaining,
    'total': total,
    'series': series,
    'interruptions': interruptions,
    'delaysMs': delaysMs,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  static TimerSnapshot? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return TimerSnapshot(
      mode: json['mode'] as String? ?? 'pomodoro',
      run: json['run'] as String? ?? 'stopped',
      remaining: json['remaining'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      series: json['series'] as int? ?? 0,
      interruptions: json['interruptions'] as int? ?? 0,
      delaysMs: json['delaysMs'] as int? ?? 0,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        json['savedAt'] as int? ?? 0,
      ),
    );
  }
}

/// JSON-файл состояния таймера в AppData.
class TimerStateStore {
  File? _file;

  Future<File> _stateFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}timer_state.json');
    _file = file;
    return file;
  }

  Future<TimerSnapshot?> load() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return null;
      return TimerSnapshot.fromJson(jsonDecode(await file.readAsString()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(TimerSnapshot snapshot) async {
    try {
      final file = await _stateFile();
      await file.writeAsString(jsonEncode(snapshot.toJson()));
    } on FileSystemException {
      // Потеря снимка таймера не критична — молча пропускаем.
    }
  }
}
