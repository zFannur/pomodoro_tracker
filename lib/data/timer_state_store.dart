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
    this.overtime = 0,
    this.startedAt,
  });

  final String mode;
  final String run;
  final int remaining;
  final int total;
  final int series;
  final int interruptions;
  final int delaysMs;
  final DateTime savedAt;

  /// Овертайм Flowtime. Без него снимок «run=running, remaining=0» при
  /// восстановлении всегда попадал в ветку «дотикал» и молча выбрасывался —
  /// вместе со всем отработанным сверх нормы временем.
  final int overtime;

  /// Реальное начало фазы: нужно, чтобы дописать помидор задним числом.
  final DateTime? startedAt;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'run': run,
    'remaining': remaining,
    'total': total,
    'series': series,
    'interruptions': interruptions,
    'delaysMs': delaysMs,
    'savedAt': savedAt.millisecondsSinceEpoch,
    if (overtime != 0) 'overtime': overtime,
    if (startedAt != null) 'startedAt': startedAt!.millisecondsSinceEpoch,
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
      overtime: json['overtime'] as int? ?? 0,
      startedAt: json['startedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int)
          : null,
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
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      // Потеря снимка таймера не критична — молча пропускаем.
    }
  }
}
