import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/app_settings.dart';
import '../../services/drive_sync_service.dart';

enum SyncStatus { disconnected, idle, syncing, error }

class SyncState extends Equatable {
  const SyncState({
    this.status = SyncStatus.disconnected,
    this.lastSync,
    this.message = '',
  });

  final SyncStatus status;
  final DateTime? lastSync;
  final String message;

  bool get connected => status != SyncStatus.disconnected;

  SyncState copyWith({SyncStatus? status, DateTime? lastSync, String? message}) {
    return SyncState(
      status: status ?? this.status,
      lastSync: lastSync ?? this.lastSync,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [status, lastSync, message];
}

/// Статус Google Drive-синка + дебаунс отправки локальных правок.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(this._service, this._settings) : super(const SyncState());

  final DriveSyncService _service;
  final AppSettings Function() _settings;
  Timer? _debounce;

  /// Старт приложения: показать сохранённое время и тихо синкнуть.
  Future<void> init() async {
    emit(state.copyWith(lastSync: await _service.storedLastSync()));
    await syncNow();
  }

  /// Локальные задачи изменились: пометить и отправить чуть погодя.
  void scheduleSync() {
    unawaited(_service.markDirty());
    _schedule(const Duration(seconds: 5));
  }

  void _schedule(Duration delay) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      if (state.connected) unawaited(syncNow());
    });
  }

  /// Синк по фокусу окна/возврату в приложение — не чаще раза в минуту.
  Future<void> syncIfStale() async {
    if (!state.connected) return;
    final last = state.lastSync;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 1)) {
      return;
    }
    await syncNow();
  }

  /// Интерактивное подключение из настроек.
  Future<void> connect() async {
    final s = _settings();
    final missing = Platform.isWindows
        ? s.syncClientId.trim().isEmpty || s.syncClientSecret.trim().isEmpty
        : false;
    if (missing) {
      emit(state.copyWith(
        status: SyncStatus.error,
        message: S.syncFillCredentials,
      ));
      return;
    }
    await syncNow(interactive: true);
  }

  Future<void> syncNow({bool interactive = false}) async {
    final before = state.status;
    emit(state.copyWith(status: SyncStatus.syncing, message: ''));
    try {
      final outcome = await _service.sync(interactive: interactive);
      switch (outcome) {
        case SyncOutcome.notConnected:
          emit(state.copyWith(status: SyncStatus.disconnected));
        case SyncOutcome.busy:
          // Синк уже идёт (например стартовый). Правка ждёт пуша — без
          // перевзвода таймера она не уехала бы до следующей правки/фокуса.
          emit(state.copyWith(status: before));
          _schedule(const Duration(seconds: 5));
        case SyncOutcome.noChanges:
        case SyncOutcome.pushed:
        case SyncOutcome.pulled:
        case SyncOutcome.merged:
          emit(state.copyWith(
            status: SyncStatus.idle,
            lastSync: DateTime.now(),
          ));
      }
    } on Exception catch (e) {
      // Вход отменён/сеть упала: без интерактива не пугаем — просто оффлайн.
      emit(state.copyWith(
        status: interactive ? SyncStatus.error : before,
        message: _explain('$e'),
      ));
    }
  }

  /// Сырой DEVELOPER_ERROR ни о чём не говорит — дописываем, что проверять.
  /// Причина всегда одна: Google не нашёл клиента под это приложение.
  String _explain(String error) {
    final config =
        error.contains('DEVELOPER_ERROR') ||
        error.contains('clientConfigurationError') ||
        error.contains('ApiException: 10');
    return config ? '$error\n\n${S.syncDeveloperErrorHint}' : error;
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    await _service.signOut();
    emit(const SyncState());
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
