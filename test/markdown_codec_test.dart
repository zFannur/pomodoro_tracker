import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';
import 'package:pomodoro_tracker/domain/entities/sprint.dart';

void main() {
  group('строка задачи плана', () {
    test('round-trip с категорией, минутами и датой', () {
      final task = PomoTask(
        description: 'Код-ревью PR 42',
        category: 'работа',
        durationMinutes: 50,
        due: DateTime(2026, 7, 18),
      );
      expect(planLine(task), '- Код-ревью PR 42 #работа ⏱ 50м 📅 2026-07-18');
      expect(parsePlanLine(planLine(task)), task);
    });

    test('строка без категории и минут получает дефолты', () {
      final task = parsePlanLine('- Просто задача', defaultDuration: 25);
      expect(task, isNotNull);
      expect(task!.category, 'прочее');
      expect(task.durationMinutes, 25);
      expect(task.due, isNull);
    });

    test('пересчёт минут в помидоры: ceil, минимум 1', () {
      const task = PomoTask(description: 'X', category: 'y', durationMinutes: 26);
      expect(task.pomos(25), 2);
      expect(task.pomos(50), 1);
      expect(
        const PomoTask(description: 'X', category: 'y', durationMinutes: 12)
            .pomos(25),
        1,
      );
    });

    test('вкладка планировщика по сроку', () {
      final now = DateTime(2026, 7, 16); // четверг
      PomoTask withDue(DateTime? due) => PomoTask(
            description: 'X',
            category: 'y',
            durationMinutes: 25,
            due: due,
          );
      expect(withDue(null).tab(now), PlannerTab.inbox);
      // Просроченное — во «Входящие».
      expect(withDue(DateTime(2026, 7, 15)).tab(now), PlannerTab.inbox);
      expect(withDue(DateTime(2026, 7, 17)).tab(now), PlannerTab.tomorrow);
      // Суббота этой недели.
      expect(withDue(DateTime(2026, 7, 18)).tab(now), PlannerTab.week);
      // Следующий понедельник — «Позже».
      expect(withDue(DateTime(2026, 7, 20)).tab(now), PlannerTab.later);
    });

    test('чекбокс-строки не считаются задачами плана', () {
      expect(parsePlanLine('- [ ] Чекбокс спринта'), isNull);
      expect(parsePlanLine('обычный текст'), isNull);
    });
  });

  group('умный ввод', () {
    // parseSmartInput живёт в tasks_cubit — здесь проверяем только формат
    // строк файла; сам разбор покрыт в timer_cubit_test-стиле ниже.
  });

  group('Задачи.md', () {
    test('round-trip: Сегодня + Планировщик', () {
      final file = TasksFile(
        todo: [
          const PomoTask(description: 'A', category: 'работа', durationMinutes: 75),
          const PomoTask(description: 'B', category: 'личное', durationMinutes: 12),
        ],
        planner: [
          PomoTask(
            description: 'C',
            category: 'прочее',
            durationMinutes: 25,
            due: DateTime(2026, 7, 17),
          ),
          const PomoTask(description: 'D', category: 'учёба', durationMinutes: 25),
        ],
      );
      final parsed = parseTasksFile(serializeTasksFile(file));
      expect(parsed, file);
    });
  });

  group('журнал дня', () {
    test('round-trip сессий: простой, прерывания, ручные отметки', () {
      final date = DateTime(2026, 7, 16);
      final log = DayLog(
        date: date,
        goal: 8,
        sessions: [
          PomoSession(
            start: DateTime(2026, 7, 16, 9, 12),
            minutes: 25,
            category: 'работа',
            task: 'Код-ревью',
          ),
          PomoSession(
            start: DateTime(2026, 7, 16, 10, 5),
            minutes: 25,
            delayMinutes: 7,
            interruptions: 2,
            category: 'личное',
            task: 'Английский | Duolingo',
            manual: true,
          ),
          // Помидор после полуночи — логический день тот же.
          PomoSession(
            start: DateTime(2026, 7, 17, 0, 30),
            minutes: 25,
            category: 'работа',
            task: 'Ночная работа',
          ),
        ],
      );
      final parsed = parseDayLog(serializeDayLog(log), date, 8);
      expect(parsed.count, 3);
      expect(parsed.minutes, 75);
      expect(parsed.delayMinutes, 7);
      expect(parsed.interruptions, 2);
      expect(parsed.sessions[1].manual, isTrue);
      expect(parsed.sessions[2].start.day, 17);
      expect(parsed.sessions[2].start.hour, 0);
      // «|» в тексте задачи не ломает таблицу и восстанавливается обратно.
      expect(parsed.sessions[1].task, 'Английский | Duolingo');
    });

    test('пустой день — фокус 0 (как в оригинале)', () {
      final parsed = parseDayLog('', DateTime(2026, 7, 16), 5);
      expect(parsed.count, 0);
      expect(parsed.focus, 0);
    });
  });

  group('формула фокуса', () {
    test('без простоев и прерываний — 100%', () {
      expect(
        focusPercent(amount: 4, minutes: 100, delayMinutes: 0, interruptions: 0),
        100,
      );
    });

    test('простой = половина работы → 75%', () {
      expect(
        focusPercent(amount: 4, minutes: 100, delayMinutes: 50, interruptions: 0),
        75,
      );
    });

    test('простой ≥ работы → 50%', () {
      expect(
        focusPercent(
          amount: 2,
          minutes: 50,
          delayMinutes: 500,
          interruptions: 0,
        ),
        50,
      );
    });

    test('прерывания дают экспоненциальный штраф', () {
      expect(
        focusPercent(amount: 2, minutes: 50, delayMinutes: 0, interruptions: 2),
        98,
      );
    });

    test('логическая дата: до 05:00 — прошлый день', () {
      expect(logicalDate(DateTime(2026, 7, 17, 0, 30)), DateTime(2026, 7, 16));
      expect(logicalDate(DateTime(2026, 7, 17, 5, 0)), DateTime(2026, 7, 17));
      expect(logicalDate(DateTime(2026, 7, 17, 12, 0)), DateTime(2026, 7, 17));
    });
  });

  group('спринт', () {
    test('round-trip цели, вехи и сделанного за неделю', () {
      final sprint = Sprint(
        id: '2026-W29',
        start: DateTime(2026, 7, 13),
        goal: 40,
        milestone: 'товар покупается живым юзером',
        doneWeek: const ['✅ 16.07 Настроить оплату #проекты'],
      );
      final fact = [
        for (var i = 0; i < 7; i++)
          DayLog(
            date: DateTime(2026, 7, 13 + i),
            goal: 8,
            sessions: [
              if (i < 3)
                PomoSession(
                  start: DateTime(2026, 7, 13 + i, 9),
                  minutes: 25,
                  category: 'работа',
                  task: 'X',
                ),
            ],
          ),
      ];
      final content = serializeSprint(
        sprint,
        fact,
        weekTasks: const [
          PomoTask(
            description: 'Задача недели',
            category: 'проекты',
            durationMinutes: 50,
            week: true,
          ),
        ],
      );
      final parsed = parseSprint(content, '2026-W29', DateTime(2026, 7, 13), 10);
      expect(parsed.goal, 40);
      expect(parsed.milestone, sprint.milestone);
      expect(parsed.doneWeek, sprint.doneWeek);

      final summary = parseSprintSummary(content);
      expect(summary, isNotNull);
      expect(summary!.fact, 3);
      expect(summary.minutes, 75);
    });

    test('маркеры 🐸 и ⭐ переживают round-trip строки задачи', () {
      const task = PomoTask(
        description: 'Лягушка недели',
        category: 'проекты',
        durationMinutes: 25,
        frog: true,
        week: true,
      );
      expect(planLine(task), '- 🐸 Лягушка недели #проекты ⏱ 25м ⭐');
      expect(parsePlanLine(planLine(task)), task);
    });
  });

  group('ISO-недели', () {
    test('известные значения', () {
      expect(isoWeekNumber(DateTime(2026, 7, 16)), 29);
      expect(sprintId(DateTime(2026, 7, 16)), '2026-W29');
      expect(mondayOf(DateTime(2026, 7, 16)), DateTime(2026, 7, 13));
      expect(sprintId(DateTime(2027, 1, 1)), '2026-W53');
      expect(sprintId(DateTime(2027, 1, 4)), '2027-W01');
    });
  });
}
