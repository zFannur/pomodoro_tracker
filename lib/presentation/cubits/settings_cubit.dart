import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories.dart';

enum SettingsStatus { loading, ready, failure }

class SettingsState extends Equatable {
  const SettingsState({
    required this.status,
    required this.settings,
    this.error = '',
  });

  final SettingsStatus status;
  final AppSettings settings;
  final String error;

  SettingsState copyWith({
    SettingsStatus? status,
    AppSettings? settings,
    String? error,
  }) {
    return SettingsState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, settings, error];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(
    this._repository, {
    required AppSettings initial,
    required this._onStoragePathChanged,
  }) : super(SettingsState(status: SettingsStatus.loading, settings: initial));

  final SettingsRepository _repository;
  final void Function(String path) _onStoragePathChanged;

  Future<void> load() async {
    final result = await _repository.load();
    result.match(
      (failure) => emit(
        state.copyWith(status: SettingsStatus.failure, error: failure.message),
      ),
      (settings) {
        _onStoragePathChanged(settings.storagePath);
        emit(state.copyWith(status: SettingsStatus.ready, settings: settings));
      },
    );
  }

  Future<void> update(AppSettings settings) async {
    final pathChanged = settings.storagePath != state.settings.storagePath;
    emit(state.copyWith(status: SettingsStatus.ready, settings: settings));
    if (pathChanged) _onStoragePathChanged(settings.storagePath);
    final result = await _repository.save(settings);
    result.match(
      (failure) => emit(
        state.copyWith(status: SettingsStatus.failure, error: failure.message),
      ),
      (_) {},
    );
  }
}
