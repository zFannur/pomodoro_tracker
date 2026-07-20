import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Один засчитанный помидор (запись истории «Сделано»).
class PomoSession extends Equatable {
  const PomoSession({
    required this.id,
    required this.start,
    required this.minutes,
    required this.category,
    required this.task,
    this.delayMinutes = 0,
    this.interruptions = 0,
    this.manual = false,
    this.frog = false,
  });

  /// Стабильный идентификатор записи. Нужен синку (union по id при слиянии
  /// двух устройств), но чинит и живой баг: без него два помидора одной
  /// минуты по одной задаче неразличимы, и правка/удаление в журнале
  /// попадали в первую совпадающую строку, а не в выбранную.
  final String id;

  final DateTime start;
  final int minutes;
  final String category;
  final String task;

  /// Простой (задержка) перед этим помидором, минуты.
  final int delayMinutes;

  /// Сколько раз помидор ставили на паузу.
  final int interruptions;

  /// Отмечен вручную через меню, а не отработан таймером
  /// (аналог флага suspicious в оригинале).
  final bool manual;

  /// Помидор работал над 🐸-задачей дня — для мягкой статы «сделал главное».
  final bool frog;

  PomoSession copyWith({
    String? id,
    DateTime? start,
    int? minutes,
    String? category,
    String? task,
    int? delayMinutes,
    int? interruptions,
    bool? manual,
    bool? frog,
  }) {
    return PomoSession(
      id: id ?? this.id,
      start: start ?? this.start,
      minutes: minutes ?? this.minutes,
      category: category ?? this.category,
      task: task ?? this.task,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      interruptions: interruptions ?? this.interruptions,
      manual: manual ?? this.manual,
      frog: frog ?? this.frog,
    );
  }

  @override
  List<Object?> get props => [
    // id первым: иначе Equatable по-прежнему считает два одинаковых
    // помидора равными и баг с правкой не той строки остаётся.
    id,
    start,
    minutes,
    category,
    task,
    delayMinutes,
    interruptions,
    manual,
    frog,
  ];
}

/// Фокус-формула оригинала: 0 при пустом дне; base = 1 − delay/(2·duration);
/// при прерываниях base = min(base, 0.99)^((amount+interruptions)/amount).
int focusPercent({
  required int amount,
  required int minutes,
  required int delayMinutes,
  required int interruptions,
}) {
  if (amount == 0) return 0;
  final delay = math.min(delayMinutes, minutes);
  var base = minutes == 0 ? 0.5 : 1 - delay / (2 * minutes);
  if (interruptions > 0) {
    base =
        math.pow(math.min(base, 0.99), (amount + interruptions) / amount)
            as double;
  }
  return (100 * base).round().clamp(0, 100);
}

/// Журнал одного дня (день длится с 05:00 до 05:00, как в оригинале).
class DayLog extends Equatable {
  const DayLog({
    required this.date,
    required this.goal,
    required this.sessions,
    this.notes = const [],
  });

  final DateTime date;

  /// Цель на день; 0 — без цели.
  final int goal;
  final List<PomoSession> sessions;

  /// Заметки «на чём встал» — снимают остаток внимания при переключении.
  final List<String> notes;

  int get count => sessions.length;

  /// В этот день работали над 🐸-задачей (сделал главное).
  bool get hasFrog => sessions.any((s) => s.frog);

  int get minutes => sessions.fold(0, (sum, s) => sum + s.minutes);

  int get delayMinutes => sessions.fold(0, (sum, s) => sum + s.delayMinutes);

  int get interruptions => sessions.fold(0, (sum, s) => sum + s.interruptions);

  int get focus => focusPercent(
    amount: count,
    minutes: minutes,
    delayMinutes: delayMinutes,
    interruptions: interruptions,
  );

  DayLog copyWith({
    List<PomoSession>? sessions,
    List<String>? notes,
    int? goal,
  }) {
    return DayLog(
      date: date,
      goal: goal ?? this.goal,
      sessions: sessions ?? this.sessions,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [date, goal, sessions, notes];
}

/// Логическая дата дня: сутки начинаются в 05:00.
DateTime logicalDate(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day - (moment.hour < 5 ? 1 : 0));
