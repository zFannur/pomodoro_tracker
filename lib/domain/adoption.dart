import 'dart:math' as math;

import '../app/help_content.dart';
import '../app/strings.dart';
import 'entities/app_settings.dart';
import 'entities/direction.dart';
import 'entities/episode.dart';
import 'entities/pomo_session.dart';
import 'entities/pomo_task.dart';
import 'entities/sprint.dart';

/// Пороги автоотметок пути внедрения (таблица «Путь внедрения» в справке).
const adoptionDirections = 2;
const adoptionLadder = 3;
const adoptionMornings = 3;
const adoptionCauses = 5;
const adoptionFrogDays = 3;
const adoptionStrategies = 3;

/// Окно «за 7 дней» — столько же, сколько знаменатель в «4 утра из 7».
const adoptionWindowDays = 7;

/// Шаги, которые приложение увидеть не может: их отмечают руками.
const manualSteps = {
  'observe.nofix',
  'exp.read',
  'own.compare',
  'own.keep',
  'own.month',
};

/// Снимок данных, по которым пути видно выполнение шагов. Собирается в UI
/// из кубитов, чтобы функция осталась чистой и тестируемой.
class AdoptionFacts {
  const AdoptionFacts({
    this.activeDirections = 0,
    this.directionsWithCategories = 0,
    this.directionsWithLadder = 0,
    this.hasSessionWindows = false,
    this.hasDistractMarks = false,
    this.aiKeySet = false,
    this.checkinMornings = 0,
    this.causeEpisodes = 0,
    this.frogDays = 0,
    this.hasExperiment = false,
    this.strategyEpisodes = 0,
    this.todayHasFirstStep = false,
    this.todayHasCue = false,
    this.previousVerdict = false,
    this.warmupUsed = false,
    this.ipsThisMonth = false,
  });

  /// Из данных кубитов. Любой источник может отсутствовать (трекера окон нет
  /// на Android, кубит не в дереве) — тогда его факты пусты.
  factory AdoptionFacts.collect({
    required DateTime now,
    List<Direction> directions = const [],
    List<Milestone> milestones = const [],
    List<DayLog> days = const [],
    List<PomoTask> todo = const [],
    Sprint? sprint,
    Sprint? previous,
    AppSettings? settings,
    bool hasDistractMarks = false,
  }) {
    final today = logicalDate(now);
    final from = DateTime(today.year, today.month, today.day - 6);
    final week = [
      for (final d in days)
        if (!d.date.isBefore(from) && !d.date.isAfter(today)) d,
    ];
    final active = [
      for (final d in directions)
        if (d.status == DirectionStatus.active) d,
    ];
    return AdoptionFacts(
      activeDirections: active.length,
      directionsWithCategories: active
          .where((d) => d.categories.isNotEmpty)
          .length,
      directionsWithLadder: active
          .where((d) => ladder(milestones, d.id).length >= adoptionLadder)
          .length,
      hasSessionWindows:
          settings != null &&
          parseSessionWindows(settings.sessionWindows).isNotEmpty,
      hasDistractMarks: hasDistractMarks,
      aiKeySet: settings != null && settings.aiKey.trim().isNotEmpty,
      checkinMornings: week.where((d) => d.checkIn.sleep != null).length,
      causeEpisodes: week.fold(
        0,
        (sum, d) => sum + d.episodes.where((e) => e.cause != null).length,
      ),
      frogDays: week
          .where((d) => d.sessions.any((s) => s.frog && !s.manual))
          .length,
      hasExperiment: sprint?.experiment != null,
      strategyEpisodes: week.fold(
        0,
        (sum, d) => sum + d.episodes.where((e) => e.strategy != null).length,
      ),
      todayHasFirstStep: todo.any((t) => t.firstStep.trim().isNotEmpty),
      todayHasCue: todo.any((t) => t.cue.trim().isNotEmpty),
      previousVerdict: previous?.experiment?.verdict != null,
      warmupUsed: days.any(
        (d) => d.episodes.any((e) => e.strategy == StrategyKind.warmup),
      ),
      ipsThisMonth: days.any(
        (d) =>
            d.date.year == today.year &&
            d.date.month == today.month &&
            d.ips.isNotEmpty,
      ),
    );
  }

  final int activeDirections;
  final int directionsWithCategories;
  final int directionsWithLadder;
  final bool hasSessionWindows;
  final bool hasDistractMarks;
  final bool aiKeySet;

  /// Утра с оценкой сна за последние 7 логических дней.
  final int checkinMornings;

  /// Эпизоды с причиной за 7 дней.
  final int causeEpisodes;

  /// Дни, где был помидор по 🐸, за 7 дней.
  final int frogDays;
  final bool hasExperiment;

  /// Эпизоды со способом за 7 дней.
  final int strategyEpisodes;
  final bool todayHasFirstStep;
  final bool todayHasCue;
  final bool previousVerdict;
  final bool warmupUsed;
  final bool ipsThisMonth;
}

/// Выполнен ли шаг. Правила — столбец «Отмечается» таблицы пути; «вручную»
/// и любой неизвестный id — по [manualChecks].
bool stepDone(String stepId, AdoptionFacts f, Set<String> manualChecks) =>
    switch (stepId) {
      'setup.dirs' => f.activeDirections >= adoptionDirections,
      'setup.cats' =>
        f.activeDirections > 0 &&
            f.directionsWithCategories == f.activeDirections,
      'setup.ladder' =>
        f.activeDirections > 0 && f.directionsWithLadder == f.activeDirections,
      'setup.windows' => f.hasSessionWindows,
      'setup.distract' => f.hasDistractMarks,
      'setup.ai' => f.aiKeySet,
      'observe.checkin' => f.checkinMornings >= adoptionMornings,
      'observe.causes' => f.causeEpisodes >= adoptionCauses,
      'observe.frog' => f.frogDays >= adoptionFrogDays,
      'exp.take' => f.hasExperiment,
      'exp.strategies' => f.strategyEpisodes >= adoptionStrategies,
      'exp.firststep' => f.todayHasFirstStep,
      'plan.ifthen' => f.todayHasCue,
      'plan.verdict' => f.previousVerdict,
      'plan.warmup' => f.warmupUsed,
      'own.scale' => f.ipsThisMonth,
      _ => manualChecks.contains(stepId),
    };

/// Шаг учитывается в этапе: необязательные его не держат, шаг «Windows»
/// на других платформах не показывается.
bool stepRequired(HelpStep step, {required bool windows}) =>
    !step.optional && (windows || !step.windowsOnly);

/// Этап пройден: выполнены все его обязательные шаги.
bool stageDone(
  HelpStage stage,
  AdoptionFacts f,
  Set<String> manual, {
  required bool windows,
}) => stage.steps
    .where((s) => stepRequired(s, windows: windows))
    .every((s) => stepDone(s.id, f, manual));

/// Индекс текущего этапа — первого, где не выполнен обязательный шаг.
/// Все выполнены → `stages.length` (путь пройден).
int currentStage(
  List<HelpStage> stages,
  AdoptionFacts f,
  Set<String> manual, {
  required bool windows,
}) {
  for (var i = 0; i < stages.length; i++) {
    if (!stageDone(stages[i], f, manual, windows: windows)) return i;
  }
  return stages.length;
}

/// «3 из 5», «4 утра из 7» — для шагов с порогом-числом; null для остальных.
String? stepProgress(String stepId, AdoptionFacts f) => switch (stepId) {
  'setup.dirs' => S.helpProgressOf(
    math.min(f.activeDirections, adoptionDirections),
    adoptionDirections,
  ),
  'observe.checkin' => S.helpProgressMornings(
    f.checkinMornings,
    adoptionWindowDays,
  ),
  'observe.causes' => S.helpProgressOf(
    math.min(f.causeEpisodes, adoptionCauses),
    adoptionCauses,
  ),
  'observe.frog' => S.helpProgressDays(f.frogDays, adoptionWindowDays),
  'exp.strategies' => S.helpProgressOf(
    math.min(f.strategyEpisodes, adoptionStrategies),
    adoptionStrategies,
  ),
  _ => null,
};
