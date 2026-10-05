import 'dart:async';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/markdown_codec.dart' show dateKey;
import '../../domain/entities/pomo_session.dart' show PomoSession, logicalDate;
import '../../services/activity_tracker.dart';

export '../../services/activity_tracker.dart' show ActivityRow;

class ActivityState extends Equatable {
  const ActivityState({
    required this.date,
    required this.isToday,
    this.rows = const [],
    this.distracting = const {},
    this.selected = const {},
  });

  /// Логическая дата (сутки с 05:00).
  final DateTime date;
  final bool isToday;

  /// Записи дня, по убыванию времени.
  final List<ActivityRow> rows;
  final Set<String> distracting;

  /// Выбранные строки для удаления: ключ 'app|title'.
  final Set<String> selected;

  bool isDistracting(ActivityRow row) => distracting.contains(row.key);

  bool isSelected(ActivityRow row) =>
      selected.contains('${row.app}|${row.title}');

  bool get isSelectionMode => selected.isNotEmpty;

  int get totalSeconds => rows.fold(0, (sum, r) => sum + r.seconds);

  int get distractingSeconds => rows
      .where(isDistracting)
      .fold(0, (sum, r) => sum + r.seconds);

  /// Доля отвлекающего времени от всего, %.
  int get distractingPercent => totalSeconds == 0
      ? 0
      : (100 * distractingSeconds / totalSeconds).round();

  /// Фокус в помидорах: доля focusSeconds не-отвлекающих от всех focusSeconds.
  /// null — помидоров за день не было, показывать нечего.
  int? get focusPercent {
    final all = rows.fold(0, (sum, r) => sum + r.focusSeconds);
    if (all == 0) return null;
    final good = rows
        .where((r) => !isDistracting(r))
        .fold(0, (sum, r) => sum + r.focusSeconds);
    return (100 * good / all).round();
  }

  ActivityState copyWith({
    DateTime? date,
    bool? isToday,
    List<ActivityRow>? rows,
    Set<String>? distracting,
    Set<String>? selected,
  }) {
    return ActivityState(
      date: date ?? this.date,
      isToday: isToday ?? this.isToday,
      rows: rows ?? this.rows,
      distracting: distracting ?? this.distracting,
      selected: selected ?? this.selected,
    );
  }

  @override
  List<Object?> get props => [date, isToday, rows, distracting, selected];
}

/// Данные трекера за выбранный день. Обновляется по сигналу трекера
/// (каждые 5 с, пока он что-то записывает); одинаковое состояние не
/// эмитится, так что простой экран не перерисовывается.
class ActivityCubit extends Cubit<ActivityState> {
  ActivityCubit(this._tracker)
    : super(ActivityState(date: logicalDate(clock.now()), isToday: true)) {
    _sub = _tracker.ticks.listen((_) => refresh());
  }

  final ActivityTracker _tracker;
  StreamSubscription<void>? _sub;

  ActivityState _build(DateTime date, {Set<String>? selected}) {
    final today = logicalDate(clock.now());
    final entries = _tracker.data.days[dateKey(date)]?.values ?? const [];
    final rows = <ActivityRow>[
      for (final e in entries)
        (
          key: e.key,
          app: e.app,
          title: e.title,
          seconds: e.seconds,
          focusSeconds: e.focusSeconds,
        ),
    ]..sort((a, b) => b.seconds.compareTo(a.seconds));
    final existingKeys = {for (final r in rows) '${r.app}|${r.title}'};
    final currentSelected = (selected ?? state.selected)
        .where(existingKeys.contains)
        .toSet();
    return ActivityState(
      date: date,
      isToday: !date.isBefore(today),
      rows: rows,
      distracting: Set.of(_tracker.data.distracting),
      selected: currentSelected,
    );
  }

  void refresh() {
    if (isClosed) return;
    // «Сегодня» следует за сменой суток, чужой день остаётся на месте.
    emit(_build(state.isToday ? logicalDate(clock.now()) : state.date));
  }

  void prevDay() {
    final d = state.date;
    emit(_build(DateTime(d.year, d.month, d.day - 1), selected: const {}));
  }

  void nextDay() {
    if (state.isToday) return;
    final d = state.date;
    emit(_build(DateTime(d.year, d.month, d.day + 1), selected: const {}));
  }

  void toggleSelected(ActivityRow row) {
    final key = '${row.app}|${row.title}';
    final next = Set<String>.of(state.selected);
    if (!next.remove(key)) {
      next.add(key);
    }
    emit(state.copyWith(selected: next));
  }

  void clearSelection() {
    if (state.selected.isEmpty) return;
    emit(state.copyWith(selected: const {}));
  }

  Future<void> deleteSelected({required bool everywhere}) async {
    if (state.selected.isEmpty) return;
    final items = <({String app, String title})>{
      for (final s in state.selected)
        (
          app: s.substring(0, s.indexOf('|')),
          title: s.substring(s.indexOf('|') + 1),
        ),
    };
    await _tracker.delete(
      items,
      day: everywhere ? null : dateKey(state.date),
    );
    clearSelection();
    refresh();
  }

  Future<void> deleteRow(ActivityRow row, {required bool everywhere}) async {
    await _tracker.delete(
      {(app: row.app, title: row.title)},
      day: everywhere ? null : dateKey(state.date),
    );
    final key = '${row.app}|${row.title}';
    if (state.selected.contains(key)) {
      final next = Set<String>.of(state.selected)..remove(key);
      emit(state.copyWith(selected: next));
    }
    refresh();
  }

  Future<void> toggleDistracting(String key) async {
    await _tracker.toggleDistracting(key);
    refresh();
  }

  /// Отрезки активности, попадающие в окно помидора [s].
  List<ActivityRow> segmentsFor(PomoSession s) {
    final dayKey = dateKey(logicalDate(s.start));
    final segments = _tracker.data.focusSegments[dayKey] ?? const [];
    final from = s.start.subtract(const Duration(minutes: 1));
    final to = s.start.add(Duration(minutes: s.minutes + 1));
    return segmentsSummary(segments, from, to);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
