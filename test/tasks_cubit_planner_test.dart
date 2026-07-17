import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/tasks_cubit.dart';
import 'package:pomodoro_tracker/services/notify_service.dart';

/// Репозиторий задач в памяти.
class _MemTasks implements TaskRepository {
  TasksFile file = const TasksFile(todo: [], planner: []);

  @override
  Future<Either<Failure, TasksFile>> load() async => Either.right(file);

  @override
  Future<Either<Failure, Unit>> save(TasksFile f) async {
    file = f;
    return Either.right(unit);
  }
}

class _MemJournal implements JournalRepository {
  @override
  Future<Either<Failure, Unit>> addSession(
    PomoSession session,
    int dailyGoal,
  ) async => Either.right(unit);

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) async =>
      Either.right(unit);

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int dailyGoal) async =>
      Either.right(DayLog(date: date, goal: dailyGoal, sessions: const []));

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int dailyGoal,
  ) async => Either.right(const []);
}

PomoTask t(String d, {DateTime? due}) =>
    PomoTask(description: d, category: 'x', durationMinutes: 25, due: due);

void main() {
  late _MemTasks repo;
  late TasksCubit cubit;

  Future<void> seed({
    List<PomoTask> todo = const [],
    List<PomoTask> planner = const [],
  }) async {
    repo = _MemTasks()..file = TasksFile(todo: todo, planner: planner);
    cubit = TasksCubit(
      repo,
      _MemJournal(),
      () => AppSettings.fromJson(const {}, fallbackPath: '.'),
      NotifyService(),
    );
    await cubit.load();
  }

  List<String> plannerNames() =>
      cubit.state.planner.map((t) => t.description).toList();

  test('plannerReorder переставляет и сохраняет', () async {
    await seed(planner: [t('a'), t('b'), t('c')]);
    await cubit.plannerReorder(0, 2);
    expect(plannerNames(), ['b', 'c', 'a']);
    expect(repo.file.planner.map((t) => t.description), ['b', 'c', 'a']);
  });

  test('plannerReorder внутри корзины не трогает чужие задачи', () async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await seed(planner: [t('a'), t('t1', due: tomorrow), t('b')]);
    // Перетащить b (инбокс) на место a (инбокс): реальные индексы 2 → 0.
    await cubit.plannerReorder(2, 0);
    expect(plannerNames(), ['b', 'a', 't1']);
    expect(cubit.state.planner[2].due, isNotNull);
  });

  test('plannerEdit меняет описание и нормализует категорию', () async {
    await seed(planner: [t('a')]);
    await cubit.plannerEdit(0, description: 'new', category: 'моя кат');
    expect(cubit.state.planner.first.description, 'new');
    expect(cubit.state.planner.first.category, 'моя-кат');
  });

  test('insertTodoAt/insertPlannerAt возвращают удалённое (undo)', () async {
    await seed(todo: [t('x'), t('y')], planner: [t('p')]);
    final removedTodo = cubit.state.todo[1];
    await cubit.removeAt(1);
    await cubit.insertTodoAt(1, removedTodo);
    expect(cubit.state.todo.map((t) => t.description), ['x', 'y']);

    final removedPlanner = cubit.state.planner[0];
    await cubit.plannerRemove(0);
    await cubit.insertPlannerAt(0, removedPlanner);
    expect(plannerNames(), ['p']);
    // Индекс за пределами — вставка в конец, не падение.
    await cubit.insertPlannerAt(99, t('q'));
    expect(plannerNames(), ['p', 'q']);
  });
}
