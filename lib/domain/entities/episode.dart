import 'package:equatable/equatable.dart';

/// Откуда пришёл сигнал.
enum EpisodeSource { idle, stop, defer, frog, distract, manual }

enum Cause { unclear, big, boring, perfect, tired, pointless, external }

enum StrategyKind {
  firstStep,
  warmup,
  ifThen,
  shrink,
  thought,
  defuse,
  value,
  rest,
  removeCue,
}

/// Снимок задачи сохраняется, даже если сама задача уже удалена.
class Episode extends Equatable {
  const Episode({
    required this.id,
    required this.at,
    required this.source,
    this.taskId = '',
    this.task = '',
    this.category = '',
    this.cause,
    this.strategy,
    this.thought = '',
    this.fact = '',
    this.alt = '',
    this.app = '',
  });

  final String id;
  final DateTime at;

  /// null — источник из более новой версии приложения ещё неизвестен.
  final EpisodeSource? source;
  final String taskId;
  final String task;
  final String category;

  /// null — на тихий сигнал ещё не ответили.
  final Cause? cause;

  /// null — способ не выбирали.
  final StrategyKind? strategy;
  final String thought;
  final String fact;
  final String alt;
  final String app;

  Episode copyWith({
    String? id,
    DateTime? at,
    EpisodeSource? source,
    String? taskId,
    String? task,
    String? category,
    Cause? cause,
    bool clearCause = false,
    StrategyKind? strategy,
    bool clearStrategy = false,
    String? thought,
    String? fact,
    String? alt,
    String? app,
  }) => Episode(
    id: id ?? this.id,
    at: at ?? this.at,
    source: source ?? this.source,
    taskId: taskId ?? this.taskId,
    task: task ?? this.task,
    category: category ?? this.category,
    cause: clearCause ? null : (cause ?? this.cause),
    strategy: clearStrategy ? null : (strategy ?? this.strategy),
    thought: thought ?? this.thought,
    fact: fact ?? this.fact,
    alt: alt ?? this.alt,
    app: app ?? this.app,
  );

  @override
  List<Object?> get props => [
    id,
    at,
    source,
    taskId,
    task,
    category,
    cause,
    strategy,
    thought,
    fact,
    alt,
    app,
  ];
}

/// Пустая оценка означает, что пользователь её ещё не дал.
class CheckIn extends Equatable {
  const CheckIn({this.sleep, this.energy, this.mood})
    : assert(sleep == null || (sleep >= 1 && sleep <= 5)),
      assert(energy == null || (energy >= 1 && energy <= 5)),
      assert(mood == null || (mood >= 1 && mood <= 5));

  final int? sleep;
  final int? energy;
  final int? mood;

  bool get isEmpty => sleep == null && energy == null && mood == null;

  CheckIn merge(CheckIn other) => CheckIn(
    sleep: other.sleep ?? sleep,
    energy: other.energy ?? energy,
    mood: other.mood ?? mood,
  );

  @override
  List<Object?> get props => [sleep, energy, mood];
}
