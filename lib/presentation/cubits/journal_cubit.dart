import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/repositories.dart';
import '../../services/notify_service.dart';

enum JournalStatus { loading, ready, failure }

/// Список «Сделано» за текущий логический день (05:00–05:00).
class JournalState extends Equatable {
  const JournalState({
    required this.status,
    this.log,
    this.categoryFilter,
    this.error = '',
  });

  final JournalStatus status;
  final DayLog? log;

  /// Фильтр по категории (null — все записи).
  final String? categoryFilter;
  final String error;

  List<PomoSession> get sessions => log?.sessions ?? const [];

  /// Записи по убыванию времени (новые сверху, как в оригинале).
  List<PomoSession> get visible {
    final list = categoryFilter == null
        ? sessions
        : sessions
              .where((s) => s.category == categoryFilter)
              .toList(growable: false);
    final sorted = [...list]..sort((a, b) => b.start.compareTo(a.start));
    return sorted;
  }

  /// Счётчики категорий: имя → число записей.
  Map<String, int> get categoryCounters {
    final result = <String, int>{};
    for (final s in sessions) {
      if (s.category.isEmpty) continue;
      result[s.category] = (result[s.category] ?? 0) + 1;
    }
    final entries = result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in entries) e.key: e.value};
  }

  JournalState copyWith({
    JournalStatus? status,
    DayLog? log,
    String? categoryFilter,
    bool clearFilter = false,
    String? error,
  }) {
    return JournalState(
      status: status ?? this.status,
      log: log ?? this.log,
      categoryFilter: clearFilter
          ? null
          : (categoryFilter ?? this.categoryFilter),
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, log, categoryFilter, error];
}

class JournalCubit extends Cubit<JournalState> {
  JournalCubit(
    this._journal,
    this._settings,
    this._notify, {
    required this._onDayChanged,
  }) : super(const JournalState(status: JournalStatus.loading)) {
    _dayWatch = Timer.periodic(const Duration(seconds: 60), (_) => _checkDay());
    _shownDate = logicalDate(DateTime.now());
  }

  final JournalRepository _journal;
  final AppSettings Function() _settings;
  final NotifyService _notify;
  final Future<void> Function() _onDayChanged;

  /// Журнал правили вручную (удалили запись, поправили минуты, очистили день).
  /// Без этого «Статистика» и «Спринт» показывали старые цифры до перезапуска —
  /// у TasksCubit такой колбэк есть, у журнала не было.
  Future<void> Function()? onJournalChanged;

  late Timer _dayWatch;
  late DateTime _shownDate;

  Future<void> refresh() async {
    final result = await _journal.day(
      logicalDate(DateTime.now()),
      _settings().dailyGoal,
    );
    result.match(
      (failure) => emit(
        state.copyWith(status: JournalStatus.failure, error: failure.message),
      ),
      (log) => emit(state.copyWith(status: JournalStatus.ready, log: log)),
    );
  }

  /// Смена логического дня (граница 05:00): список очищается,
  /// прошлый день остаётся в markdown-журнале.
  Future<void> _checkDay() async {
    final today = logicalDate(DateTime.now());
    if (today == _shownDate) return;
    _shownDate = today;
    await refresh();
    await _onDayChanged();
    await _notify.event(_settings(), title: S.appTitle, body: S.dayCleared);
  }

  void setCategoryFilter(String? category) {
    if (state.categoryFilter == category) {
      emit(state.copyWith(clearFilter: true));
    } else {
      emit(state.copyWith(categoryFilter: category));
    }
  }

  Future<void> editEntry(
    PomoSession entry, {
    String? category,
    String? task,
    int? minutes,
  }) async {
    final log = state.log;
    if (log == null) return;
    final sessions = [...log.sessions];
    // Поиск по id, а не по значению: две одинаковые записи одной минуты
    // раньше приводили к правке первой совпавшей, а не выбранной.
    final index = sessions.indexWhere((s) => s.id == entry.id);
    if (index < 0) return;
    sessions[index] = entry.copyWith(
      category: category,
      task: task,
      minutes: minutes,
    );
    await _saveDay(sessions);
  }

  Future<void> deleteEntry(PomoSession entry) async {
    final log = state.log;
    if (log == null) return;
    final sessions = [...log.sessions]..removeWhere((s) => s.id == entry.id);
    await _saveDay(sessions);
  }

  /// Прописать категорию/описание записи во все пустые записи дня.
  Future<void> fillBlanks(PomoSession source) async {
    final log = state.log;
    if (log == null || (source.category.isEmpty && source.task.isEmpty)) return;
    final sessions = [
      for (final s in log.sessions)
        if (s.category.isEmpty && s.task.isEmpty)
          s.copyWith(category: source.category, task: source.task)
        else
          s,
    ];
    await _saveDay(sessions);
  }

  Future<void> clearToday() async {
    await _saveDay(const []);
  }

  /// Заметка «на чём встал» — снимает остаток внимания при переключении.
  Future<void> addNote(String text) async {
    final log = state.log;
    final trimmed = text.trim();
    if (log == null || trimmed.isEmpty) return;
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final updated = log.copyWith(notes: [...log.notes, '$stamp — $trimmed']);
    emit(state.copyWith(status: JournalStatus.ready, log: updated));
    final result = await _journal.saveDay(updated);
    result.match(
      (failure) => emit(
        state.copyWith(status: JournalStatus.failure, error: failure.message),
      ),
      (_) {},
    );
    await onJournalChanged?.call();
  }

  Future<void> _saveDay(List<PomoSession> sessions) async {
    final log = state.log;
    if (log == null) return;
    final updated = log.copyWith(
      goal: _settings().dailyGoal,
      sessions: sessions,
    );
    emit(state.copyWith(status: JournalStatus.ready, log: updated));
    final result = await _journal.saveDay(updated);
    result.match(
      (failure) => emit(
        state.copyWith(status: JournalStatus.failure, error: failure.message),
      ),
      (_) {},
    );
    await onJournalChanged?.call();
  }

  @override
  Future<void> close() {
    _dayWatch.cancel();
    return super.close();
  }
}
