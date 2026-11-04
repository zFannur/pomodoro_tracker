import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart' show sprintId;
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/experiment.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';

class Memory implements InsightRepository, JournalRepository, SprintRepository {
  final days = <DateTime, DayLog>{};
  final sprints = <String, Sprint>{};
  DayLog log(DateTime date) =>
      days[date] ?? DayLog(date: date, goal: 8, sessions: const []);

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int dailyGoal,
  ) async => right([
    for (final day in days.values)
      if (!day.date.isBefore(from) && !day.date.isAfter(to)) day,
  ]);
  @override
  Future<Either<Failure, Sprint>> current(DateTime now, int defaultGoal) async {
    final start = DateTime(now.year, now.month, now.day - now.weekday + 1);
    return right(
      sprints[sprintId(now)] ??
          Sprint(id: sprintId(now), start: start, goal: defaultGoal),
    );
  }

  @override
  Future<Either<Failure, List<SprintSummary>>> history() async => right([
    for (final s in sprints.values)
      SprintSummary(id: s.id, goal: s.goal, fact: 0, minutes: 0),
  ]);
  @override
  Future<Either<Failure, Unit>> addEpisode(Episode e) async {
    final date = logicalDate(e.at);
    final d = log(date);
    days[date] = d.copyWith(episodes: [...d.episodes, e]);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setCheckIn(DateTime day, CheckIn ck) async {
    final d = log(day);
    days[day] = d.copyWith(checkIn: d.checkIn.merge(ck));
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> saveExperiment(
    String id,
    Experiment? exp,
  ) async {
    final s = sprints[id];
    if (s != null) {
      sprints[id] = s.copyWith(experiment: exp, clearExperiment: exp == null);
    }
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 11, 4, 10);
  late Memory repo;
  late InsightCubit cubit;
  setUp(() {
    repo = Memory();
    cubit = InsightCubit(
      repo,
      repo,
      repo,
      () => AppSettings.fromJson(const {}, fallbackPath: '.'),
    );
  });
  tearDown(() => cubit.close());

  test(
    'добавление эпизода и неделя наблюдения',
    () => withClock(Clock.fixed(now), () async {
      await cubit.refresh();
      expect(cubit.observation, isTrue);
      final episode = await cubit.addEpisode(source: EpisodeSource.manual);
      expect(cubit.todayEpisodes, [episode]);
    }),
  );
  test(
    'ожидающий эпизод: причина, возраст, порядок и граница',
    () => withClock(Clock.fixed(now), () async {
      final d = logicalDate(now);
      Episode e(String id, int minutes, {Cause? cause}) => Episode(
        id: id,
        at: now.subtract(Duration(minutes: minutes)),
        source: EpisodeSource.idle,
        cause: cause,
      );
      repo.days[d] = repo
          .log(d)
          .copyWith(
            episodes: [
              e('old', 61),
              e('boundary', 60),
              e('answered', 1, cause: Cause.big),
            ],
          );
      await cubit.refresh();
      expect(cubit.pendingEpisode(EpisodeSource.idle)?.id, 'boundary');
      repo.days[d] = repo
          .log(d)
          .copyWith(
            episodes: [
              e('old', 61),
              e('answered', 1, cause: Cause.big),
            ],
          );
      await cubit.refresh();
      expect(cubit.pendingEpisode(EpisodeSource.idle), isNull);
    }),
  );
  test(
    'способ эксперимента идёт первым только среди кандидатов',
    () => withClock(Clock.fixed(now), () async {
      final start = DateTime(2026, 11, 2);
      repo.sprints[sprintId(now)] = Sprint(
        id: sprintId(now),
        start: start,
        goal: 40,
        experiment: const Experiment(
          hypothesis: 'test',
          strategy: StrategyKind.ifThen,
          metric: InsightMetric.firstStart,
        ),
      );
      await cubit.refresh();
      expect(cubit.ranked(Cause.unclear).first, StrategyKind.ifThen);
      expect(cubit.ranked(Cause.tired), isNot(contains(StrategyKind.ifThen)));
    }),
  );
  test(
    'самочувствие объединяет поля',
    () => withClock(Clock.fixed(now), () async {
      await cubit.setCheckIn(const CheckIn(sleep: 4));
      await cubit.setCheckIn(const CheckIn(energy: 2));
      expect(cubit.checkIn, const CheckIn(sleep: 4, energy: 2));
    }),
  );
}
