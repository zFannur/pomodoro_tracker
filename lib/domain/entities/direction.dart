import 'package:equatable/equatable.dart';

import 'pomo_session.dart';

/// Статус направления.
/// Пауза направления — явная и важная: она снимает вину за временно
/// заброшенное направление и делает оставшиеся активные ощутимо движущимися.
enum DirectionStatus { active, paused, done }

/// Направление (стратегический фокус на 3–12 месяцев) — уровень выше недели.
/// Направление держит категории, а не ссылки из задач: поэтому вся прошлая
/// история журнала атрибутируется задним числом, без миграции данных
/// и без добавления нового поля в [PomoTask].
class Direction extends Equatable {
  const Direction({
    required this.id,
    required this.name,
    this.note = '',
    this.horizon,
    this.status = DirectionStatus.active,
    this.order = 0,
    this.categories = const [],
  });

  final String id;
  final String name;

  /// Имя заметки в Obsidian для связи с контекстом и материалами.
  final String note;

  /// Месяц-цель (горизонт планирования направления).
  final DateTime? horizon;

  final DirectionStatus status;
  final int order;

  /// Категории задач и помидоров, привязанные к этому направлению.
  final List<String> categories;

  Direction copyWith({
    String? id,
    String? name,
    String? note,
    DateTime? horizon,
    bool clearHorizon = false,
    DirectionStatus? status,
    int? order,
    List<String>? categories,
  }) {
    return Direction(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      horizon: clearHorizon ? null : (horizon ?? this.horizon),
      status: status ?? this.status,
      order: order ?? this.order,
      categories: categories ?? this.categories,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    note,
    horizon,
    status,
    order,
    categories,
  ];
}

/// Ступень лестницы направления (веха).
/// У вех нет дат в календаре, только относительный порядок: на месяцы вперёд
/// планируются исходы, а не действия, иначе план протухает за две недели.
/// Веха проверяется бинарно (через [doneSprint]) и формулируется как результат,
/// а не деятельность.
class Milestone extends Equatable {
  const Milestone({
    required this.id,
    required this.directionId,
    required this.title,
    this.order = 0,
    this.doneSprint = '',
    this.doneAt,
    this.proofs = const [],
  });

  final String id;
  final String directionId;
  final String title;
  final int order;

  /// Идентификатор недели закрытия вида `2026-W29`. Пусто — веха открыта.
  final String doneSprint;

  /// Точный момент закрытия для расчёта темпа движения.
  final DateTime? doneAt;

  /// Строки закрытых ⭐-задач, которыми ступень закрыта.
  /// Формат: «✅ 16.09 Настроить оплату #проекты».
  final List<String> proofs;

  bool get done => doneSprint.isNotEmpty;

  Milestone copyWith({
    String? id,
    String? directionId,
    String? title,
    int? order,
    String? doneSprint,
    DateTime? doneAt,
    List<String>? proofs,
    bool reopen = false,
  }) {
    return Milestone(
      id: id ?? this.id,
      directionId: directionId ?? this.directionId,
      title: title ?? this.title,
      order: order ?? this.order,
      doneSprint: reopen ? '' : (doneSprint ?? this.doneSprint),
      doneAt: reopen ? null : (doneAt ?? this.doneAt),
      proofs: proofs ?? this.proofs,
    );
  }

  @override
  List<Object?> get props => [
    id,
    directionId,
    title,
    order,
    doneSprint,
    doneAt,
    proofs,
  ];
}

/// Категория → id направления. Категория, попавшая в два направления,
/// достаётся тому, что раньше по `order`: атрибуция помидора обязана быть
/// однозначной, иначе доли внимания не сложатся в 100%.
Map<String, String> categoryIndex(List<Direction> directions) {
  final sorted = [...directions]..sort((a, b) => a.order.compareTo(b.order));
  final result = <String, String>{};
  for (final dir in sorted) {
    for (final cat in dir.categories) {
      result.putIfAbsent(cat, () => dir.id);
    }
  }
  return result;
}

/// Вехи направления по возрастанию `order`.
List<Milestone> ladder(List<Milestone> all, String directionId) {
  final list = [
    for (final m in all)
      if (m.directionId == directionId) m,
  ];
  list.sort((a, b) => a.order.compareTo(b.order));
  return list;
}

/// Следующая незакрытая ступень. null — лестница пройдена.
Milestone? nextOpen(List<Milestone> all, String directionId) {
  final lad = ladder(all, directionId);
  for (final m in lad) {
    if (!m.done) return m;
  }
  return null;
}

/// Темп: сколько вех направления закрывается за 30 дней. Считается по
/// фактическим закрытиям за последние [days] дней, а не по оценкам —
/// система измеряет реальную скорость, а не обещанную. 0 без закрытий.
double closureRate(
  List<Milestone> all,
  String directionId,
  DateTime now, {
  int days = 84,
}) {
  if (days <= 0) return 0.0;
  final cutoff = now.subtract(Duration(days: days));
  var closed = 0;
  for (final m in all) {
    if (m.directionId != directionId || !m.done) continue;
    final at = m.doneAt;
    if (at != null && !at.isBefore(cutoff) && !at.isAfter(now)) {
      closed++;
    }
  }
  if (closed == 0) return 0.0;
  return (closed * 30.0) / days;
}

/// Прогноз закрытия направления при текущем темпе.
/// null — темпа нет (0 закрытий за окно) либо открытых вех не осталось.
DateTime? directionEta(
  List<Milestone> all,
  String directionId,
  DateTime now, {
  int days = 84,
}) {
  final lad = ladder(all, directionId);
  final openCount = lad.where((m) => !m.done).length;
  if (openCount == 0) return null;
  final rate = closureRate(all, directionId, now, days: days);
  if (rate <= 0) return null;
  final daysNeeded = (openCount * 30.0 / rate).round();
  return now.add(Duration(days: daysNeeded));
}

/// Помидоры по направлениям за период. Ключ — id направления;
/// ключ `''` — помидоры вне направлений.
Map<String, int> pomosByDirection(
  List<DayLog> days,
  List<Direction> directions,
) {
  final catIdx = categoryIndex(directions);
  final result = <String, int>{
    for (final d in directions) d.id: 0,
    '': 0,
  };
  for (final day in days) {
    for (final session in day.sessions) {
      final dirId = catIdx[session.category] ?? '';
      result[dirId] = (result[dirId] ?? 0) + 1;
    }
  }
  return result;
}

/// Лента закрытий: id недели (`2026-W29`) → вехи, закрытые в эту неделю.
Map<String, List<Milestone>> closuresByWeek(List<Milestone> all) {
  final result = <String, List<Milestone>>{};
  for (final m in all) {
    if (m.done) {
      result.putIfAbsent(m.doneSprint, () => []).add(m);
    }
  }
  return result;
}
