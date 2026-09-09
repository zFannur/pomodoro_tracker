import 'dart:math' show max;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/json_data_repository.dart' show JsonDataRepository, newId;
import '../../domain/entities/direction.dart';
import '../../domain/entities/pomo_session.dart' show DayLog, logicalDate;
import '../../domain/repositories.dart';

/// Статус загрузки и сохранения состояния курса.
enum DirectionsStatus { loading, ready, failure }

/// Состояние экрана и логики «Курса» (направления и вехи).
/// Вся расчётная логика делегируется чистым функциям из `direction.dart`,
/// чтобы гарантировать согласованность и исключить дублирование.
class DirectionsState extends Equatable {
  const DirectionsState({
    required this.status,
    this.directions = const [],
    this.milestones = const [],
    this.recentDays = const [],
    this.error = '',
    this.reviewedMonth = '',
  });

  final DirectionsStatus status;
  final List<Direction> directions;
  final List<Milestone> milestones;

  /// Журнал за последние 30 дней для подсчёта бюджета внимания.
  final List<DayLog> recentDays;
  final String error;

  /// Месяц, за который месячный разбор уже был показан и скрыт (вид '2026-09').
  final String reviewedMonth;

  /// Активные направления, отсортированные по возрастанию [Direction.order].
  List<Direction> get active {
    final list = [
      for (final d in directions)
        if (d.status == DirectionStatus.active) d,
    ];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Направления на паузе, отсортированные по возрастанию [Direction.order].
  List<Direction> get paused {
    final list = [
      for (final d in directions)
        if (d.status == DirectionStatus.paused) d,
    ];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Завершённые направления, отсортированные по возрастанию [Direction.order].
  List<Direction> get finished {
    final list = [
      for (final d in directions)
        if (d.status == DirectionStatus.done) d,
    ];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Следующая незакрытая веха направления. null — лестница пройдена.
  Milestone? next(String directionId) => nextOpen(milestones, directionId);

  /// Прогресс вех направления (количество закрытых и общее число вех).
  ({int done, int total}) progress(String directionId) {
    final lad = ladder(milestones, directionId);
    final doneCount = lad.where((m) => m.done).length;
    return (done: doneCount, total: lad.length);
  }

  /// Поиск вехи по её уникальному [id].
  Milestone? milestoneById(String id) {
    for (final m in milestones) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Родительское направление для переданной вехи [m].
  Direction? directionOf(Milestone m) {
    for (final d in directions) {
      if (d.id == m.directionId) return d;
    }
    return null;
  }

  /// Направление, к которому относится данная категория задач/помидоров.
  /// При коллизиях приоритет у направления с меньшим `order` (через [categoryIndex]).
  Direction? directionForCategory(String category) {
    final dirId = categoryIndex(directions)[category];
    if (dirId == null) return null;
    for (final d in directions) {
      if (d.id == dirId) return d;
    }
    return null;
  }

  /// Лента закрытий: id недели (`2026-W29`) → список закрытых в эту неделю вех.
  Map<String, List<Milestone>> get closuresByWeekMap =>
      closuresByWeek(milestones);

  DirectionsState copyWith({
    DirectionsStatus? status,
    List<Direction>? directions,
    List<Milestone>? milestones,
    List<DayLog>? recentDays,
    String? error,
    String? reviewedMonth,
  }) {
    return DirectionsState(
      status: status ?? this.status,
      directions: directions ?? this.directions,
      milestones: milestones ?? this.milestones,
      recentDays: recentDays ?? this.recentDays,
      error: error ?? this.error,
      reviewedMonth: reviewedMonth ?? this.reviewedMonth,
    );
  }

  @override
  List<Object?> get props => [
    status,
    directions,
    milestones,
    recentDays,
    error,
    reviewedMonth,
  ];
}

/// Управление стратегическими направлениями и вехами («Курс»).
/// Следует шаблону [SprintCubit]: оптимистичное обновление состояния в памяти,
/// затем асинхронная фиксация через [DirectionRepository.saveCourse].
class DirectionsCubit extends Cubit<DirectionsState> {
  DirectionsCubit(
    this._repository, [
    this._journalRepository,
    this._getMonthRollover,
    this._setMonthRollover,
  ]) : super(const DirectionsState(status: DirectionsStatus.loading));

  final DirectionRepository _repository;
  final JournalRepository? _journalRepository;
  final Future<String?> Function()? _getMonthRollover;
  final Future<void> Function(String month)? _setMonthRollover;

  /// Первичная загрузка или обновление данных курса из репозитория.
  /// Также загружает журнал за последние 30 дней для расчёта бюджета внимания.
  Future<void> refresh() async {
    final result = await _repository.loadCourse();
    var days = state.recentDays;
    if (_journalRepository != null) {
      final today = logicalDate(DateTime.now());
      // За последние 30 дней: от (today - 29 дней) до today включительно.
      final from = DateTime(today.year, today.month, today.day - 29);
      final daysResult = await _journalRepository.range(from, today, 0);
      daysResult.match(
        (_) {},
        (loaded) => days = loaded,
      );
    }
    String? reviewedMonth;
    if (_getMonthRollover != null) {
      reviewedMonth = await _getMonthRollover();
    } else if (_repository case final JsonDataRepository jsonRepo) {
      final mRes = await jsonRepo.monthRollover();
      reviewedMonth = mRes.getOrElse((_) => null);
    }
    result.match(
      (failure) => emit(
        state.copyWith(
          status: DirectionsStatus.failure,
          error: failure.message,
        ),
      ),
      (course) => emit(
        state.copyWith(
          status: DirectionsStatus.ready,
          directions: course.directions,
          milestones: course.milestones,
          recentDays: days,
          reviewedMonth: reviewedMonth ?? state.reviewedMonth,
        ),
      ),
    );
  }

  /// Добавить новое направление.
  /// Статус по умолчанию — [DirectionStatus.active], порядок — следующий за максимальным.
  Future<void> addDirection(String name) async {
    final nextOrder = state.directions.isEmpty
        ? 0
        : state.directions.map((d) => d.order).reduce(max) + 1;
    final dir = Direction(
      id: newId(),
      name: name.trim(),
      order: nextOrder,
      status: DirectionStatus.active,
    );
    await _save(directions: [...state.directions, dir]);
  }

  /// Обновить поля существующего направления.
  Future<void> updateDirection(Direction d) async {
    final updated = [
      for (final dir in state.directions)
        if (dir.id == d.id) d else dir,
    ];
    await _save(directions: updated);
  }

  /// Изменить статус направления (активно, пауза, завершено).
  Future<void> setStatus(String id, DirectionStatus status) async {
    final updated = [
      for (final dir in state.directions)
        if (dir.id == id) dir.copyWith(status: status) else dir,
    ];
    await _save(directions: updated);
  }

  /// Переставить направление и перенумеровать [Direction.order] подряд с 0,
  /// чтобы исключить пробелы и коллизии индексов при перетаскивании.
  Future<void> reorderDirections(int oldIndex, int newIndex) async {
    final list = [...state.directions]..sort((a, b) => a.order.compareTo(b.order));
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    final target = newIndex.clamp(0, list.length);
    list.insert(target, item);
    final reordered = [
      for (var i = 0; i < list.length; i++)
        list[i].copyWith(order: i),
    ];
    await _save(directions: reordered);
  }

  /// Удалить направление вместе со всеми принадлежащими ему вехами:
  /// вехи не могут существовать без родительского направления.
  Future<void> deleteDirection(String id) async {
    final remainingDirs = [
      for (final d in state.directions)
        if (d.id != id) d,
    ];
    final remainingMiles = [
      for (final m in state.milestones)
        if (m.directionId != id) m,
    ];
    await _save(directions: remainingDirs, milestones: remainingMiles);
  }

  /// Добавить веху в указанное направление.
  /// Порядок [Milestone.order] вычисляется локально внутри этого направления (max + 1).
  Future<void> addMilestone(String directionId, String title) async {
    final dirMilestones = [
      for (final m in state.milestones)
        if (m.directionId == directionId) m,
    ];
    final nextOrder = dirMilestones.isEmpty
        ? 0
        : dirMilestones.map((m) => m.order).reduce(max) + 1;
    final milestone = Milestone(
      id: newId(),
      directionId: directionId,
      title: title.trim(),
      order: nextOrder,
    );
    await _save(milestones: [...state.milestones, milestone]);
  }

  /// Обновить данные вехи.
  Future<void> updateMilestone(Milestone m) async {
    final updated = [
      for (final item in state.milestones)
        if (item.id == m.id) m else item,
    ];
    await _save(milestones: updated);
  }

  /// Переставить веху внутри направления и перенумеровать её [Milestone.order]
  /// строго подряд от 0. Вехи других направлений остаются без изменений.
  Future<void> reorderMilestones(
    String directionId,
    int oldIndex,
    int newIndex,
  ) async {
    final dirMilestones = ladder(state.milestones, directionId);
    if (oldIndex < 0 || oldIndex >= dirMilestones.length) return;
    final item = dirMilestones.removeAt(oldIndex);
    final target = newIndex.clamp(0, dirMilestones.length);
    dirMilestones.insert(target, item);
    final reorderedDir = [
      for (var i = 0; i < dirMilestones.length; i++)
        dirMilestones[i].copyWith(order: i),
    ];
    var dirIdx = 0;
    final updated = [
      for (final m in state.milestones)
        if (m.directionId == directionId)
          reorderedDir[dirIdx++]
        else
          m,
    ];
    await _save(milestones: updated);
  }

  /// Удалить веху по идентификатору.
  Future<void> deleteMilestone(String id) async {
    final remaining = [
      for (final m in state.milestones)
        if (m.id != id) m,
    ];
    await _save(milestones: remaining);
  }

  /// Зафиксировать закрытие вехи в конкретном спринте [sprintId] и в момент времени [at].
  /// Связку со Sprint.milestoneId этот метод намеренно не трогает — это зона T04.
  Future<void> closeMilestone(
    String id,
    String sprintId,
    DateTime at,
  ) async {
    final updated = [
      for (final m in state.milestones)
        if (m.id == id)
          m.copyWith(doneSprint: sprintId, doneAt: at)
        else
          m,
    ];
    await _save(milestones: updated);
  }

  /// Открыть веху заново, сбросив отметку о спринте и дате закрытия.
  Future<void> reopenMilestone(String id) async {
    final updated = [
      for (final m in state.milestones)
        if (m.id == id)
          m.copyWith(reopen: true)
        else
          m,
    ];
    await _save(milestones: updated);
  }

  /// Дописать строку доказательства в веху, если её там ещё нет.
  /// Пустой milestoneId, пустая строка доказательства или ненайденная веха —
  /// тихо ничего не делает.
  Future<void> addProof(String milestoneId, String line) async {
    if (milestoneId.isEmpty || line.trim().isEmpty) return;
    final index = state.milestones.indexWhere((m) => m.id == milestoneId);
    if (index < 0) return;
    final target = state.milestones[index];
    if (target.proofs.contains(line)) return;
    final updated = [
      for (var i = 0; i < state.milestones.length; i++)
        if (i == index)
          target.copyWith(proofs: [...target.proofs, line])
        else
          state.milestones[i],
    ];
    await _save(milestones: updated);
  }

  /// Скрыть баннер месячного разбора до следующего месяца и зафиксировать отметку в rollover.
  Future<void> dismissMonthReview(String month) async {
    emit(state.copyWith(reviewedMonth: month));
    if (_setMonthRollover != null) {
      await _setMonthRollover(month);
    } else if (_repository case final JsonDataRepository jsonRepo) {
      await jsonRepo.markRollover(month: month);
    }
  }

  /// Внутреннее сохранение: обновляет состояние в памяти и пишет на диск/в хранилище.
  /// В случае ошибки переводит статус в [DirectionsStatus.failure] с сообщением.
  Future<void> _save({
    List<Direction>? directions,
    List<Milestone>? milestones,
  }) async {
    final nextDirs = directions ?? state.directions;
    final nextMiles = milestones ?? state.milestones;
    emit(
      state.copyWith(
        status: DirectionsStatus.ready,
        directions: nextDirs,
        milestones: nextMiles,
      ),
    );
    final result = await _repository.saveCourse((
      directions: nextDirs,
      milestones: nextMiles,
    ));
    result.match(
      (failure) => emit(
        state.copyWith(
          status: DirectionsStatus.failure,
          error: failure.message,
        ),
      ),
      (_) {},
    );
  }
}
