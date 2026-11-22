import 'package:clock/clock.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/episode.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/presentation/cubits/insight_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/timer_cubit.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';
import 'package:pomodoro_tracker/services/sound_service.dart';

import 'screen_fakes.dart';

AppSettings episodeSettings() =>
    AppSettings.fromJson(const {}, fallbackPath: '.');

class EpisodeInsight extends InsightCubit {
  EpisodeInsight({this.observing = false, this.order, this.counts = const {}})
    : super(FakeInsights(), FakeJournal(), FakeSprints(), episodeSettings) {
    emit(const InsightState(status: InsightStatus.ready));
  }

  final bool observing;
  final List<StrategyKind>? order;
  final Map<StrategyKind, ({int tries, int wins})> counts;
  final episodes = <Episode>[];
  bool failWrite = false;
  int causeUpdates = 0;

  @override
  bool get observation => observing;
  @override
  List<StrategyKind> ranked(Cause c) => order ?? super.ranked(c);
  @override
  Map<StrategyKind, ({int tries, int wins})> get stats => counts;
  @override
  Future<void> refresh() async {}

  void publish() => emit(
    state.copyWith(
      status: InsightStatus.ready,
      days: [
        DayLog(
          date: logicalDate(clock.now()),
          goal: 0,
          sessions: const [],
          episodes: [...episodes],
        ),
      ],
    ),
  );

  @override
  Future<Episode> addEpisode({
    required EpisodeSource source,
    PomoTask? task,
    String app = '',
    Cause? cause,
    String thought = '',
    DateTime? at,
  }) async {
    final e = Episode(
      id: 'episode-${episodes.length}',
      at: at ?? clock.now(),
      source: source,
      taskId: task?.id ?? '',
      task: task?.description ?? '',
      category: task?.category ?? '',
      app: app,
      cause: cause,
      thought: thought,
    );
    if (failWrite) {
      emit(
        state.copyWith(status: InsightStatus.failure, error: 'write failed'),
      );
    } else {
      episodes.add(e);
      publish();
    }
    return e;
  }

  @override
  Future<void> setCause(String id, Cause c, {String thought = ''}) async {
    causeUpdates++;
    final i = episodes.indexWhere((e) => e.id == id);
    if (i >= 0) episodes[i] = episodes[i].copyWith(cause: c, thought: thought);
    publish();
  }

  @override
  Future<void> setStrategy(
    String id,
    StrategyKind k, {
    String fact = '',
    String alt = '',
  }) async {
    final i = episodes.indexWhere((e) => e.id == id);
    if (i >= 0) {
      episodes[i] = episodes[i].copyWith(strategy: k, fact: fact, alt: alt);
    }
    publish();
  }
}

class EpisodeTasks extends TasksCubit {
  EpisodeTasks()
    : super(FakeTasks(), FakeJournal(), episodeSettings, NotifyService());
  final plans = <({String id, String? step, String? cue, String? time})>[];
  final smaller = <String>[];
  final inbox = <String>[];
  bool? countedDeferral;

  void seed({
    List<PomoTask> todo = const [],
    List<PomoTask> planner = const [],
  }) =>
      emit(TasksState(status: TasksStatus.ready, todo: todo, planner: planner));
  @override
  Future<void> load() async {}
  @override
  Future<void> setPlan(
    String taskId, {
    String? firstStep,
    String? cue,
    String? cueAt,
  }) async {
    plans.add((id: taskId, step: firstStep, cue: cue, time: cueAt));
    await super.setPlan(taskId, firstStep: firstStep, cue: cue, cueAt: cueAt);
  }

  @override
  Future<void> addSmaller(PomoTask parent, String description) async {
    smaller.add(description);
    await super.addSmaller(parent, description);
  }

  @override
  Future<void> add(
    String raw, {
    required String fallbackCategory,
    bool toPlanner = false,
    DateTime? due,
    bool forceBottom = false,
  }) async {
    if (toPlanner) inbox.add(raw);
    await super.add(
      raw,
      fallbackCategory: fallbackCategory,
      toPlanner: toPlanner,
      due: due,
      forceBottom: forceBottom,
    );
  }

  @override
  Future<void> postpone(
    int index,
    PlannerTab tab, {
    bool countDeferral = true,
  }) async {
    countedDeferral = countDeferral;
    await super.postpone(index, tab, countDeferral: countDeferral);
  }
}

class EpisodeTimer extends TimerCubit {
  EpisodeTimer()
    : super(
        settings: episodeSettings,
        sound: SoundService(),
        notify: NotifyService(),
        store: FakeTimerStore(),
        hasTodos: () => true,
        onPomodoroComplete: (_) async {},
      );

  final warmups = <int>[];
  final rests = <int>[];
  int starts = 0;
  int resumes = 0;
  int stops = 0;

  void seed({
    TimerRun run = TimerRun.stopped,
    int delay = 0,
    int remaining = 1500,
    TimerMode mode = TimerMode.pomodoro,
  }) => emit(
    state.copyWith(run: run, delaysMs: delay, remaining: remaining, mode: mode),
  );
  @override
  void startWarmup(int minutes) {
    warmups.add(minutes);
    seed(run: TimerRun.running, remaining: minutes * 60);
  }

  @override
  void startRest(int minutes) {
    rests.add(minutes);
    seed(
      run: TimerRun.running,
      remaining: minutes * 60,
      mode: TimerMode.shortBreak,
    );
  }

  @override
  void start() {
    starts++;
    seed(run: TimerRun.running);
  }

  @override
  void resume() {
    resumes++;
    seed(run: TimerRun.running, remaining: state.remaining);
  }

  @override
  void stop() {
    stops++;
    seed();
  }
}
