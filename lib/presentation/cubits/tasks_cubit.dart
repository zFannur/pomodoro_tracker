import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../data/json_data_repository.dart' show newId;
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/pomo_session.dart';
import '../../domain/entities/pomo_task.dart';
import '../../domain/repositories.dart';
import '../../services/notify_service.dart';
import 'timer_cubit.dart' show PomodoroResult;

enum TasksStatus { loading, ready, failure }

/// Удалённая задача в корзине: помнит, куда восстанавливать — в «Сегодня»
/// или в планировщик (сохраняет исходный бакет через due).
class TrashedTask extends Equatable {
  const TrashedTask({required this.task, required this.fromPlanner});

  final PomoTask task;
  final bool fromPlanner;

  @override
  List<Object?> get props => [task, fromPlanner];
}

class TasksState extends Equatable {
  const TasksState({
    required this.status,
    this.todo = const [],
    this.planner = const [],
    this.trash = const [],
    this.categoryFilter,
    this.error = '',
  });

  final TasksStatus status;

  /// Список «Запланировано»: первая задача — текущая.
  final List<PomoTask> todo;

  /// Планировщик: задачи с датами (вкладки вычисляются из due).
  final List<PomoTask> planner;

  /// Корзина: последние удалённые задачи (новые — в начале). Живёт только
  /// в памяти сессии — ponytail: не переживает перезапуск, апгрейд на
  /// персистентную корзину — если это когда-нибудь станет реальной болью.
  final List<TrashedTask> trash;

  /// Активный фильтр по категории (null — все).
  final String? categoryFilter;
  final String error;

  PomoTask? get current => todo.isEmpty ? null : todo.first;

  List<PomoTask> get visibleTodo => categoryFilter == null
      ? todo
      : todo.where((t) => t.category == categoryFilter).toList(growable: false);

  /// Счётчики категорий: имя → сумма помидоров задач.
  Map<String, int> categoryCounters(int pomodoroMinutes) {
    final result = <String, int>{};
    for (final t in todo) {
      result[t.category] = (result[t.category] ?? 0) + t.pomos(pomodoroMinutes);
    }
    final entries = result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in entries) e.key: e.value};
  }

  TasksState copyWith({
    TasksStatus? status,
    List<PomoTask>? todo,
    List<PomoTask>? planner,
    List<TrashedTask>? trash,
    String? categoryFilter,
    bool clearFilter = false,
    String? error,
  }) {
    return TasksState(
      status: status ?? this.status,
      todo: todo ?? this.todo,
      planner: planner ?? this.planner,
      trash: trash ?? this.trash,
      categoryFilter: clearFilter
          ? null
          : (categoryFilter ?? this.categoryFilter),
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    todo,
    planner,
    trash,
    categoryFilter,
    error,
  ];
}

/// Разбор умного ввода «#категория описание ~N» (также ::N).
({String? category, String description, int? pomos}) parseSmartInput(
  String raw,
) {
  var text = raw.trim();
  String? category;
  final catMatch = RegExp(r'^#(\S+)\s+').firstMatch(text);
  if (catMatch != null) {
    category = catMatch.group(1);
    text = text.substring(catMatch.end);
  }
  int? pomos;
  final amountMatch = RegExp(r'\s*(?:~|::)(\d+)\s*$').firstMatch(text);
  if (amountMatch != null) {
    pomos = int.tryParse(amountMatch.group(1)!);
    text = text.substring(0, amountMatch.start);
  }
  return (category: category, description: text.trim(), pomos: pomos);
}

class TasksCubit extends Cubit<TasksState> {
  TasksCubit(this._tasks, this._journal, this._settings, this._notify)
    : super(const TasksState(status: TasksStatus.loading));

  final TaskRepository _tasks;
  final JournalRepository _journal;
  final AppSettings Function() _settings;
  final NotifyService _notify;

  /// Вызывается, когда ⭐-задача недели полностью закрыта (для спринта).
  Future<void> Function(String line)? onWeeklyClosed;

  /// Ручная отметка «сделано» дописала запись в журнал. Таймер идёт своим
  /// путём (onPomodoroComplete), а здесь без этого журнал и статистика
  /// не перечитывались — задача исчезала из «Сегодня» будто в никуда.
  Future<void> Function()? onHistoryWritten;

  int get _pomodoroMinutes => _settings().scheme.pomodoro;

  /// ⭐-задачи недели из обоих списков.
  List<PomoTask> weekTasks() => [
    ...state.todo.where((t) => t.week),
    ...state.planner.where((t) => t.week),
  ];

  Future<void> _notifyWeeklyClosed(PomoTask task) async {
    final now = DateTime.now();
    await onWeeklyClosed?.call(
      '✅ ${now.day.toString().padLeft(2, '0')}.'
      '${now.month.toString().padLeft(2, '0')} ${task.description} '
      '#${task.category}',
    );
  }

  Future<void> load() async {
    final result = await _tasks.load();
    result.match(
      (failure) => emit(
        state.copyWith(status: TasksStatus.failure, error: failure.message),
      ),
      (file) => emit(
        state.copyWith(
          status: TasksStatus.ready,
          todo: file.todo,
          planner: file.planner,
        ),
      ),
    );
  }

  // -- добавление ------------------------------------------------------------

  /// Добавить из строки умного ввода. [fallbackCategory] — из дропдауна.
  Future<void> add(
    String raw, {
    required String fallbackCategory,
    bool toPlanner = false,
    DateTime? due,
    bool forceBottom = false,
  }) async {
    final parsed = parseSmartInput(raw);
    if (parsed.description.isEmpty) return;
    final settings = _settings();
    final category = (parsed.category ?? fallbackCategory).trim().isEmpty
        ? 'прочее'
        : (parsed.category ?? fallbackCategory).trim().replaceAll(' ', '-');
    final baseMinutes = settings.schemeFor(category).pomodoro;
    // Потолок 300 минут — как в оригинале.
    final duration = parsed.pomos == null
        ? baseMinutes
        : math.min(300, parsed.pomos! * baseMinutes);
    final task = PomoTask(
      description: parsed.description.length > 255
          ? parsed.description.substring(0, 255)
          : parsed.description,
      category: category.length > 255 ? category.substring(0, 255) : category,
      durationMinutes: math.max(1, duration),
      due: due,
    );
    if (toPlanner) {
      await _persist(planner: [...state.planner, task]);
      return;
    }
    final top = settings.tasksTop && !forceBottom;
    final todo = [...state.todo];
    // Слияние с крайней задачей, если описание и категория совпадают.
    final edgeIndex = top ? 0 : todo.length - 1;
    if (todo.isNotEmpty &&
        todo[edgeIndex].description == task.description &&
        todo[edgeIndex].category == task.category) {
      todo[edgeIndex] = todo[edgeIndex].copyWith(
        durationMinutes: todo[edgeIndex].durationMinutes + task.durationMinutes,
      );
      await _persist(todo: todo);
      return;
    }
    if (top) {
      todo.insert(0, task);
    } else {
      todo.add(task);
    }
    await _persist(todo: todo);
  }

  // -- операции над задачами TODO ---------------------------------------------

  Future<void> plus(int index, {int count = 1}) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    todo[index] = todo[index].copyWith(
      durationMinutes: math.min(
        3000,
        todo[index].durationMinutes + count * _pomodoroMinutes,
      ),
    );
    await _persist(todo: todo);
  }

  Future<void> minus(int index, {int count = 1}) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final task = todo[index];
    final rest = task.durationMinutes - count * _pomodoroMinutes;
    var trash = state.trash;
    if (rest <= 0) {
      todo.removeAt(index);
      // Минус не пишет в журнал (в отличие от markDone/таймера) — без
      // корзины удаление здесь было бы никак не отслеживаемым.
      trash = _trashed(task, fromPlanner: false);
      if (task.week) await _notifyWeeklyClosed(task);
    } else {
      todo[index] = task.copyWith(durationMinutes: rest);
    }
    await _persist(todo: todo, trash: trash);
  }

  /// 🐸 Лягушка дня: одна на список, всегда наверху.
  Future<void> toggleFrog(int index) async {
    var todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final target = todo[index];
    final makeFrog = !target.frog;
    // identical, не == : после split в списке бывают Equatable-равные копии.
    todo = [
      for (final t in todo)
        identical(t, target)
            ? t.copyWith(frog: makeFrog)
            : t.copyWith(frog: false),
    ];
    if (makeFrog) {
      final frog = todo.removeAt(index);
      todo.insert(0, frog);
    }
    await _persist(todo: todo);
  }

  /// Новое утро: лягушка выбирается заново.
  Future<void> clearFrogs() async {
    if (!state.todo.any((t) => t.frog)) return;
    await _persist(todo: [for (final t in state.todo) t.copyWith(frog: false)]);
  }

  /// Новая неделя: звёзды спринта снимаются, выбираются заново из вехи.
  Future<void> clearWeekFlags() async {
    final hasTodo = state.todo.any((t) => t.week);
    final hasPlanner = state.planner.any((t) => t.week);
    if (!hasTodo && !hasPlanner) return;
    await _persist(
      todo: hasTodo
          ? [for (final t in state.todo) t.copyWith(week: false)]
          : null,
      planner: hasPlanner
          ? [for (final t in state.planner) t.copyWith(week: false)]
          : null,
    );
  }

  /// ⭐ Задача спринта.
  Future<void> toggleWeek(int index, {bool inPlanner = false}) async {
    final list = inPlanner ? [...state.planner] : [...state.todo];
    if (index < 0 || index >= list.length) return;
    list[index] = list[index].copyWith(week: !list[index].week);
    await _persist(
      todo: inPlanner ? null : list,
      planner: inPlanner ? list : null,
    );
  }

  /// Разбить: 25м → 13м (остаётся) + 12м (копия следом).
  Future<void> split(int index) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final task = todo[index];
    final half = (task.durationMinutes / 2).ceil();
    if (task.durationMinutes > half) {
      todo[index] = task.copyWith(durationMinutes: task.durationMinutes - half);
    }
    todo.insert(index + 1, task.copyWith(durationMinutes: half));
    await _persist(todo: todo);
  }

  /// Объединить со следующей по списку (последнюю — с первой).
  Future<void> merge(int index) async {
    final todo = [...state.todo];
    if (todo.length < 2 || index < 0 || index >= todo.length) return;
    final nextIndex = (index + 1) % todo.length;
    final source = todo[index];
    final target = todo[nextIndex];
    final joined = target.description.endsWith('.')
        ? '${target.description} ${source.description}'
        : '${target.description}. ${source.description}';
    todo[nextIndex] = target.copyWith(
      description: joined,
      durationMinutes: target.durationMinutes + source.durationMinutes,
    );
    todo.removeAt(index);
    await _persist(todo: todo);
  }

  /// Отметить как выполненное: один помидор (или всю задачу целиком).
  Future<void> markDone(int index, {bool whole = false}) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final task = todo[index];
    final chunk = whole
        ? task.durationMinutes
        : math.min(_pomodoroMinutes, task.durationMinutes);
    final rest = task.durationMinutes - chunk;
    if (rest <= 0) {
      todo.removeAt(index);
      if (task.week) await _notifyWeeklyClosed(task);
    } else {
      todo[index] = task.copyWith(durationMinutes: rest);
    }
    await _persist(todo: todo);
    await _writeHistory(
      minutes: chunk,
      category: task.category,
      description: task.description,
      delayMs: 0,
      interruptions: 0,
      manual: true,
      frog: task.frog,
    );
    await onHistoryWritten?.call();
  }

  Future<void> edit(int index, {String? description, String? category}) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    todo[index] = todo[index].copyWith(
      description: description,
      category: category?.trim().replaceAll(' ', '-'),
    );
    await _persist(todo: todo);
  }

  Future<void> removeAt(int index) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final removed = todo.removeAt(index);
    await _persist(
      todo: todo,
      trash: _trashed(removed, fromPlanner: false),
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final todo = [...state.todo];
    if (oldIndex < 0 || oldIndex >= todo.length) return;
    final task = todo.removeAt(oldIndex);
    todo.insert(math.min(newIndex, todo.length), task);
    await _persist(todo: todo);
  }

  /// Очистить «Сегодня» целиком — все задачи уходят в корзину одним разом.
  Future<void> clearTodo() async {
    if (state.todo.isEmpty) return;
    var trash = state.trash;
    for (final t in state.todo) {
      trash = _trashed(t, fromPlanner: false, into: trash);
    }
    await _persist(todo: [], trash: trash);
  }

  void setCategoryFilter(String? category) {
    if (state.categoryFilter == category) {
      emit(state.copyWith(clearFilter: true));
    } else {
      emit(state.copyWith(categoryFilter: category));
    }
  }

  // -- планировщик -------------------------------------------------------------

  /// Отложить задачу из TODO в планировщик.
  Future<void> postpone(int index, PlannerTab tab) async {
    final todo = [...state.todo];
    if (index < 0 || index >= todo.length) return;
    final task = todo.removeAt(index);
    await _persist(
      todo: todo,
      planner: [
        ...state.planner,
        task.copyWith(due: _dueFor(tab), clearDue: tab == PlannerTab.inbox),
      ],
    );
  }

  /// Дата для вкладки — как в оригинале: завтра / конец недели / после неё.
  DateTime? _dueFor(PlannerTab tab) {
    final now = DateTime.now();
    return switch (tab) {
      PlannerTab.inbox => null,
      PlannerTab.tomorrow => DateTime(now.year, now.month, now.day + 1),
      PlannerTab.week => DateTime(
        now.year,
        now.month,
        now.day + math.max(1, 7 - now.weekday),
      ),
      // Минимум +2 дня: в сб/вс «понедельник» — это завтра, а «позже» ≠ завтра.
      PlannerTab.later => DateTime(
        now.year,
        now.month,
        now.day + math.max(2, 8 - now.weekday),
      ),
    };
  }

  /// Перенести задачу планировщика в «Сегодня».
  Future<void> plannerToToday(int index) async {
    final planner = [...state.planner];
    if (index < 0 || index >= planner.length) return;
    final task = planner.removeAt(index).copyWith(clearDue: true);
    final todo = _settings().tasksTop
        ? [task, ...state.todo]
        : [...state.todo, task];
    await _persist(todo: todo, planner: planner);
  }

  Future<void> plannerMove(int index, PlannerTab tab) async {
    final planner = [...state.planner];
    if (index < 0 || index >= planner.length) return;
    planner[index] = planner[index].copyWith(
      due: _dueFor(tab),
      clearDue: tab == PlannerTab.inbox,
    );
    await _persist(planner: planner);
  }

  Future<void> plannerRemove(int index) async {
    final planner = [...state.planner];
    if (index < 0 || index >= planner.length) return;
    final removed = planner.removeAt(index);
    await _persist(
      planner: planner,
      trash: _trashed(removed, fromPlanner: true),
    );
  }

  /// Перестановка внутри планировщика (реальные индексы; при drag внутри
  /// корзины относительный порядок остальных корзин не меняется).
  Future<void> plannerReorder(int oldIndex, int newIndex) async {
    final planner = [...state.planner];
    if (oldIndex < 0 || oldIndex >= planner.length) return;
    final task = planner.removeAt(oldIndex);
    planner.insert(math.min(newIndex, planner.length), task);
    await _persist(planner: planner);
  }

  Future<void> plannerEdit(
    int index, {
    String? description,
    String? category,
  }) async {
    final planner = [...state.planner];
    if (index < 0 || index >= planner.length) return;
    planner[index] = planner[index].copyWith(
      description: description,
      category: category?.trim().replaceAll(' ', '-'),
    );
    await _persist(planner: planner);
  }

  /// Восстановить задачу из корзины — наверх «Сегодня» или в планировщик,
  /// откуда она была удалена (используется и снекбаром «Отменить», и
  /// экраном «Корзина» — единая точка восстановления).
  Future<void> restoreFromTrash(TrashedTask entry) async {
    // Без этой проверки повторный клик (снекбар + позже корзина на ту же
    // запись) вставил бы задачу дважды — filter ниже сам по себе не спасает.
    if (!state.trash.any((t) => identical(t, entry))) return;
    final trash = state.trash.where((t) => !identical(t, entry)).toList();
    if (entry.fromPlanner) {
      await _persist(planner: [entry.task, ...state.planner], trash: trash);
      return;
    }
    final todo = [...state.todo];
    // Пока задача лежала в корзине, лягушку могли передать другой — инвариант
    // «одна 🐸» важнее восстановления флага (последний выбор побеждает).
    final restored = entry.task.frog && todo.any((t) => t.frog)
        ? entry.task.copyWith(frog: false)
        : entry.task;
    todo.insert(0, restored);
    await _persist(todo: todo, trash: trash);
  }

  // -- завершение помидора таймером ---------------------------------------------

  /// Верхняя задача получает запись истории; её оценка уменьшается.
  Future<void> completeFromTimer(PomodoroResult result) async {
    final settings = _settings();
    final todo = [...state.todo];
    final current = todo.isEmpty ? null : todo.first;
    if (current != null) {
      final f = math.max(result.workedMinutes, settings.scheme.pomodoro);
      if (settings.completeRemove || current.durationMinutes > f) {
        final rest = current.durationMinutes - f;
        if (rest <= 0) {
          todo.removeAt(0);
          if (current.week) await _notifyWeeklyClosed(current);
        } else {
          todo[0] = current.copyWith(durationMinutes: rest);
        }
        await _persist(todo: todo);
      }
    }
    await _writeHistory(
      minutes: result.workedMinutes,
      category: current?.category ?? '',
      description: current?.description ?? '',
      delayMs: result.delayMs,
      interruptions: result.interruptions,
      manual: false,
      startedAt: result.startedAt,
      frog: current?.frog ?? false,
    );
    if (state.todo.isEmpty && current != null) {
      await _notify.event(settings, title: S.appTitle, body: S.todoEmptyDone);
    }
  }

  // -- история -------------------------------------------------------------------

  Future<void> _writeHistory({
    required int minutes,
    required String category,
    required String description,
    required int delayMs,
    required int interruptions,
    required bool manual,
    DateTime? startedAt,
    bool frog = false,
  }) async {
    final settings = _settings();
    final now = DateTime.now();
    var duration = math.max(1, minutes);
    // Старт: у таймера — реальный; у ручной — назад от «сейчас»,
    // но не раньше 05:00 текущего логического дня (иначе уедет во вчера).
    DateTime startFor(int d) {
      var start = startedAt ?? now.subtract(Duration(minutes: d));
      if (startedAt == null) {
        final dayStart = logicalDate(now).add(const Duration(hours: 5));
        if (start.isBefore(dayStart)) start = dayStart;
      }
      return start;
    }

    // Один и тот же логический день для чтения лога и для записи —
    // иначе анти-чит/простой/цель считаются по чужому дню.
    final day = logicalDate(startFor(duration));
    final dayResult = await _journal.day(day, settings.dailyGoal);
    final log = dayResult.getOrElse(
      (_) => DayLog(date: day, goal: settings.dailyGoal, sessions: const []),
    );
    // Анти-накрутка: не-ручная запись не длиннее паузы с прошлой записи.
    if (log.sessions.isNotEmpty && !manual) {
      final last = log.sessions.last;
      final lastCreated = last.start.add(Duration(minutes: last.minutes));
      final sinceLast = now.difference(lastCreated).inMinutes;
      // Отрицательный sinceLast (правленая вручную запись «из будущего»)
      // не должен резать честный помидор до 1 минуты.
      if (sinceLast > 0) duration = math.max(1, math.min(duration, sinceLast));
    }
    // Простой: не больше длительности; у первой записи дня — 0.
    final delayMin = log.sessions.isEmpty
        ? 0
        : math.min(duration, delayMs ~/ 60000);
    final session = PomoSession(
      id: newId(),
      start: startFor(duration),
      minutes: duration,
      category: category,
      task: description,
      delayMinutes: delayMin,
      interruptions: interruptions,
      manual: manual,
      frog: frog,
    );
    final writeResult = await _journal.addSession(session, settings.dailyGoal);
    writeResult.match(
      (failure) => emit(
        state.copyWith(status: TasksStatus.failure, error: failure.message),
      ),
      (_) {},
    );
    // Дневная цель достигнута — поздравление.
    if (settings.dailyGoal > 0 && log.count + 1 == settings.dailyGoal) {
      await _notify.event(settings, title: S.appTitle, body: S.goalCompleted);
    }
  }

  bool get hasTodos => state.todo.isNotEmpty;

  /// Индекс конкретного инстанса (identical): защита от устаревших индексов
  /// в колбэках меню/диалогов и от Equatable-равных дубликатов после split.
  int todoIndexOf(PomoTask task) =>
      state.todo.indexWhere((t) => identical(t, task));

  int plannerIndexOf(PomoTask task) =>
      state.planner.indexWhere((t) => identical(t, task));

  /// Сколько последних удалённых задач помнит корзина.
  static const _trashCap = 30;

  /// Положить задачу в корзину (новые — в начале, старше [_trashCap] —
  /// забываются). [into] — явный аккумулятор для пакетного удаления
  /// (несколько задач одной операцией, см. [clearTodo]).
  List<TrashedTask> _trashed(
    PomoTask task, {
    required bool fromPlanner,
    List<TrashedTask>? into,
  }) {
    final updated = [
      TrashedTask(task: task, fromPlanner: fromPlanner),
      ...(into ?? state.trash),
    ];
    return updated.length > _trashCap
        ? updated.sublist(0, _trashCap)
        : updated;
  }

  // Очередь записи на диск: без неё параллельные _persist (например, быстрые
  // подряд клики) могут завершиться в обратном порядке и более старый снимок
  // молча перезапишет новый — самый опасный класс бага для этих данных.
  Future<void> _writeQueue = Future.value();

  Future<void> _persist({
    List<PomoTask>? todo,
    List<PomoTask>? planner,
    List<TrashedTask>? trash,
  }) async {
    emit(
      state.copyWith(
        status: TasksStatus.ready,
        todo: todo ?? state.todo,
        planner: planner ?? state.planner,
        trash: trash ?? state.trash,
      ),
    );
    final snapshot = TasksFile(todo: state.todo, planner: state.planner);
    final completion = _writeQueue.then((_) => _tasks.saveTasks(snapshot));
    _writeQueue = completion.then((_) {}, onError: (_) {});
    final result = await completion;
    result.match(
      (failure) => emit(
        state.copyWith(status: TasksStatus.failure, error: failure.message),
      ),
      (_) {},
    );
  }
}
