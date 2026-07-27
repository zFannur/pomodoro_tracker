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
    this.hasSession = false,
  });

  final SyncStatus status;
  final DateTime? lastSync;
  final String message;

  /// Есть ли живая сессия. Раньше это было «статус ≠ disconnected», из-за чего
  /// промежуточный `syncing` и `error` считались подключением: гварды переставали
  /// защищать, и на Android каждая попытка открывала ещё один системный диалог.
  final bool hasSession;

  bool get connected => hasSession;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSync,
    String? message,
    bool? hasSession,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSync: lastSync ?? this.lastSync,
      message: message ?? this.message,
      hasSession: hasSession ?? this.hasSession,
    );
  }

  @override
  List<Object?> get props => [status, lastSync, message, hasSession];
}

/// Статус Google Drive-синка + дебаунс отправки локальных правок.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(this._service, this._settings) : super(const SyncState());

  final DriveSyncService _service;
  final AppSettings Function() _settings;
  Timer? _debounce;

  /// Пользователь нажал «Отключить». Признак «настроен» переживает disconnect
  /// (поля настроек остаются), поэтому без этого флага автосинк продолжал бы
  /// лезть в Google каждые 5 секунд после явного отключения.
  bool _offByUser = false;

  /// Синк уже идёт, а правка ждёт отправки. Раньше на `busy` взводился слепой
  /// таймер, который через 5 секунд гарантированно открывал ещё один диалог.
  bool _pending = false;

  /// Синк настроен: есть чем авторизоваться. Не то же самое, что «подключён».
  bool get _configured {
    final s = _settings();
    return Platform.isWindows
        ? s.syncClientId.trim().isNotEmpty &&
              s.syncClientSecret.trim().isNotEmpty
        : s.syncServerClientId.trim().isNotEmpty;
  }

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
      // По `_configured`, а не по `connected`: одна неудачная тихая авторизация
      // не должна глушить отправку до конца сеанса — правки просто копились бы
      // молча, и «сделанное» с телефона не уезжало бы никогда.
      if (_configured && !_offByUser) unawaited(syncNow());
    });
  }

  /// Синк по фокусу окна/возврату в приложение — не чаще раза в минуту.
  Future<void> syncIfStale() async {
    if (!_configured || _offByUser) return;
    // Показ системной шторки Google сам даёт paused→resumed, а resumed зовёт
    // этот метод. Без проверки «проход уже идёт» возврат из диалога запускал
    // следующий диалог.
    if (_service.running) return;
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
      emit(
        state.copyWith(
          status: SyncStatus.error,
          message: S.syncFillCredentials,
        ),
      );
      return;
    }
    _offByUser = false;
    await syncNow(interactive: true);
  }

  Future<void> syncNow({bool interactive = false}) async {
    final before = state.status;
    emit(state.copyWith(status: SyncStatus.syncing, message: ''));
    try {
      final outcome = await _service.sync(interactive: interactive);
      switch (outcome) {
        case SyncOutcome.notConnected:
          // Сессии сейчас нет — но это не «синк выключен»: следующая правка
          // или фокус попробуют снова (гварды смотрят на _configured).
          emit(
            state.copyWith(status: SyncStatus.disconnected, hasSession: false),
          );
        case SyncOutcome.busy:
          // Синк уже идёт. Отмечаем, что есть чего ждать, и повторим ровно
          // один раз — по завершении текущего прохода, а не по слепому таймеру.
          _pending = true;
          emit(state.copyWith(status: before));
        case SyncOutcome.noChanges:
        case SyncOutcome.pushed:
        case SyncOutcome.pulled:
        case SyncOutcome.merged:
          emit(
            state.copyWith(
              status: SyncStatus.idle,
              lastSync: DateTime.now(),
              hasSession: true,
            ),
          );
      }
    } on Exception catch (e) {
      // Вход отменён/сеть упала: без интерактива не пугаем — просто оффлайн.
      emit(
        state.copyWith(
          status: interactive ? SyncStatus.error : before,
          message: _explain('$e'),
          hasSession: false,
        ),
      );
    }
    // Пока шёл этот проход, кто-то просил ещё один — отдаём долг здесь,
    // без таймера: иначе на Android повтор снова открывал диалог авторизации.
    if (_pending && !_service.running) {
      _pending = false;
      if (_configured && !_offByUser) await syncNow();
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
    _pending = false;
    // Явное «Отключить» должно пережить то, что креды остались в настройках:
    // иначе автосинк тут же полез бы обратно в Google.
    _offByUser = true;
    await _service.signOut();
    emit(const SyncState());
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
