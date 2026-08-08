import 'dart:async';

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
  Future<Either<Failure, Unit>> saveTasks(TasksFile f) async {
    file = f;
    return Either.right(unit);
  }
}

/// Первая запись искусственно медленная — воспроизводит гонку, при которой
/// более старый снимок мог бы завершиться позже и молча затереть новый.
class _RacyTasks extends _MemTasks {
  var _first = true;

  @override
  Future<Either<Failure, Unit>> saveTasks(TasksFile f) async {
    if (_first) {
      _first = false;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return super.saveTasks(f);
  }
}

class _MemJournal implements JournalRepository {
  final List<PomoSession> written = [];

  @override
  Future<Either<Failure, Unit>> addSession(
    PomoSession session,
    int dailyGoal,
  ) async {
    written.add(session);
    return Either.right(unit);
  }

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

PomoTask t(String d, {DateTime? due, int minutes = 25}) =>
    PomoTask(description: d, category: 'x', durationMinutes: minutes, due: due);

void main() {
  late _MemTasks repo;
  late _MemJournal journal;
  late TasksCubit cubit;

  Future<void> seed({
    List<PomoTask> todo = const [],
    List<PomoTask> planner = const [],
  }) async {
    repo = _MemTasks()..file = TasksFile(todo: todo, planner: planner);
    journal = _MemJournal();
    cubit = TasksCubit(
      repo,
      journal,
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

  test('removeAt/plannerRemove кладут в корзину, restoreFromTrash возвращает',
      () async {
    await seed(todo: [t('x'), t('y')], planner: [t('p')]);
    await cubit.removeAt(1);
    expect(cubit.state.todo.map((t) => t.description), ['x']);
    expect(cubit.state.trash, hasLength(1));
    expect(cubit.state.trash.first.task.description, 'y');
    expect(cubit.state.trash.first.fromPlanner, isFalse);

    await cubit.restoreFromTrash(cubit.state.trash.first);
    expect(cubit.state.todo.map((t) => t.description), ['y', 'x']);
    expect(cubit.state.trash, isEmpty);

    await cubit.plannerRemove(0);
    expect(plannerNames(), isEmpty);
    expect(cubit.state.trash.single.fromPlanner, isTrue);

    await cubit.restoreFromTrash(cubit.state.trash.single);
    expect(plannerNames(), ['p']);
    expect(cubit.state.trash, isEmpty);
  });

  test('minus упирается в один помидор и НЕ удаляет задачу', () async {
    await seed(todo: [t('только один помидор')]);
    // Раньше один minus съедал задачу целиком: нажатие рядом с «прибавить»
    // необратимо теряло данные, без подтверждения и без отмены.
    await cubit.minus(0);
    expect(cubit.state.todo.single.description, 'только один помидор');
    expect(cubit.state.todo.single.durationMinutes, 25);
    expect(cubit.state.trash, isEmpty);
  });

  test('minus с большим шагом тоже не уводит ниже одного помидора', () async {
    await seed(todo: [t('две штуки', minutes: 50)]);
    await cubit.minus(0, count: 4);
    expect(cubit.state.todo.single.durationMinutes, 25);
    expect(cubit.state.trash, isEmpty);
  });

  test('minus у короткой задачи не раздувает её до помидора', () async {
    await seed(todo: [t('короткая', minutes: 10)]);
    await cubit.minus(0);
    expect(cubit.state.todo.single.durationMinutes, 10);
  });

  test('удаление осталось явным действием', () async {
    await seed(todo: [t('удалить меня')]);
    await cubit.removeAt(0);
    expect(cubit.state.todo, isEmpty);
    expect(cubit.state.trash.single.task.description, 'удалить меня');
  });

  test('clearTodo переносит все задачи «Сегодня» в корзину разом', () async {
    await seed(todo: [t('a'), t('b'), t('c')]);
    await cubit.clearTodo();
    expect(cubit.state.todo, isEmpty);
    expect(cubit.state.trash.map((e) => e.task.description).toSet(), {
      'a',
      'b',
      'c',
    });
    expect(cubit.state.trash.every((e) => !e.fromPlanner), isTrue);
  });

  test('restoreFromTrash игнорирует индекс — вставка всегда в конец/начало,'
      ' не падает на несуществующей записи', () async {
    await seed(todo: [t('x')]);
    await cubit.removeAt(0);
    final entry = cubit.state.trash.single;
    await cubit.restoreFromTrash(entry);
    expect(cubit.state.todo.single.description, 'x');
    // Повторный вызов той же (уже отсутствующей) записи — no-op, не падает.
    await cubit.restoreFromTrash(entry);
    expect(cubit.state.todo.single.description, 'x');
  });

  test('markDone пишет в журнал и дёргает onHistoryWritten', () async {
    await seed(todo: [t('закрыть руками')]);
    var refreshed = 0;
    cubit.onHistoryWritten = () async => refreshed++;
    await cubit.markDone(0, whole: true);
    // Задача ушла из «Сегодня»…
    expect(cubit.state.todo, isEmpty);
    // …но не в никуда: запись в журнале есть.
    expect(journal.written.single.task, 'закрыть руками');
    expect(journal.written.single.manual, isTrue);
    // Без этого журнал и статистика показали бы её только после перезапуска.
    expect(refreshed, 1);
  });

  test('запись на диск сериализована: медленная первая не затирает вторую',
      () async {
    final racy = _RacyTasks()..file = const TasksFile(todo: [], planner: []);
    final racyCubit = TasksCubit(
      racy,
      _MemJournal(),
      () => AppSettings.fromJson(const {}, fallbackPath: '.'),
      NotifyService(),
    );
    await racyCubit.load();
    // Первый add() запускает медленную запись и НЕ дожидается её (fire-and-
    // forget, как реально делает UI); второй стартует почти сразу следом.
    unawaited(racyCubit.add('a', fallbackCategory: 'x'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await racyCubit.add('b', fallbackCategory: 'x');
    // Без сериализации файл содержал бы только 'a' (медленная запись
    // финишировала бы последней и перезаписала бы более полный снимок).
    // Порядок не важен (tasksTop) — важно, что обе задачи выжили.
    expect(racy.file.todo.map((t) => t.description).toSet(), {'a', 'b'});
  });
}
