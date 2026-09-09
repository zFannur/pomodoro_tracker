import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/markdown_codec.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
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
      const task = PomoTask(
        description: 'X',
        category: 'y',
        durationMinutes: 26,
      );
      expect(task.pomos(25), 2);
      expect(task.pomos(50), 1);
      expect(
        const PomoTask(
          description: 'X',
          category: 'y',
          durationMinutes: 12,
        ).pomos(25),
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
      // Срок наступил или прошёл — отдельная корзина «Пора». Раньше такие
      // задачи падали во «Входящие» и терялись среди задач вообще без даты.
      expect(withDue(DateTime(2026, 7, 15)).tab(now), PlannerTab.due);
      expect(withDue(DateTime(2026, 7, 16)).tab(now), PlannerTab.due);
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
          const PomoTask(
            description: 'A',
            category: 'работа',
            durationMinutes: 75,
          ),
          const PomoTask(
            description: 'B',
            category: 'личное',
            durationMinutes: 12,
          ),
        ],
        planner: [
          PomoTask(
            description: 'C',
            category: 'прочее',
            durationMinutes: 25,
            due: DateTime(2026, 7, 17),
          ),
          const PomoTask(
            description: 'D',
            category: 'учёба',
            durationMinutes: 25,
          ),
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
            id: 's1',
            start: DateTime(2026, 7, 16, 9, 12),
            minutes: 25,
            category: 'работа',
            task: 'Код-ревью',
            frog: true,
          ),
          PomoSession(
            id: 's2',
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
            id: 's3',
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
      // 🐸-флаг лягушки переживает round-trip, а не-лягушки — нет.
      expect(parsed.sessions[0].frog, isTrue);
      expect(parsed.sessions[0].task, 'Код-ревью');
      expect(parsed.sessions[1].frog, isFalse);
      expect(parsed.hasFrog, isTrue);
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
        focusPercent(
          amount: 4,
          minutes: 100,
          delayMinutes: 0,
          interruptions: 0,
        ),
        100,
      );
    });

    test('простой = половина работы → 75%', () {
      expect(
        focusPercent(
          amount: 4,
          minutes: 100,
          delayMinutes: 50,
          interruptions: 0,
        ),
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
                  id: 'f$i',
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
      final parsed = parseSprint(
        content,
        '2026-W29',
        DateTime(2026, 7, 13),
        10,
      );
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

  group('Курс.md', () {
    test('закрытая и открытая веха сериализуются в правильные чекбоксы', () {
      final directions = [
        const Direction(
          id: 'pomo',
          name: 'Помидоро Трекер',
          note: 'Направления/Помидоро Трекер',
          order: 0,
          categories: ['проекты', 'работа'],
        ),
      ];
      final milestones = [
        Milestone(
          id: 'm1',
          directionId: 'pomo',
          title: 'Синк без потерь данных',
          order: 0,
          doneSprint: '2026-W29',
          doneAt: DateTime(2026, 7, 16),
        ),
        const Milestone(
          id: 'm2',
          directionId: 'pomo',
          title: 'Курс: направления и лестницы вех',
          order: 1,
        ),
      ];
      final md = serializeCourse(
        directions,
        milestones,
        now: DateTime(2026, 7, 20),
      );
      expect(md, contains('### 1. Помидоро Трекер\n'));
      expect(md, contains('- заметка: [[Направления/Помидоро Трекер]]\n'));
      expect(md, contains('- категории: проекты, работа\n'));
      expect(md, contains('- веха 1 из 2'));
      expect(md, contains('- [x] Синк без потерь данных `2026-W29`\n'));
      expect(md, contains('- [ ] Курс: направления и лестницы вех\n'));
    });

    test('направление без горизонта/заметки/категорий не даёт пустых строк', () {
      const directions = [
        Direction(
          id: 'clean',
          name: 'Чистое направление',
          order: 0,
        ),
      ];
      final md = serializeCourse(directions, const []);
      expect(md, contains('### 1. Чистое направление\n- веха 0 из 0\n'));
      expect(md, isNot(contains('- горизонт:')));
      expect(md, isNot(contains('- заметка:')));
      expect(md, isNot(contains('- категории:')));
      expect(md, isNot(contains('\n\n\n')));
    });

    test('порядок направлений и вех — по order', () {
      final directions = [
        const Direction(id: 'd3', name: 'Третье', order: 30),
        const Direction(id: 'd1', name: 'Первое', order: 10),
        const Direction(id: 'd2', name: 'Второе', order: 20),
        const Direction(
          id: 'p2',
          name: 'Пауза 2',
          order: 2,
          status: DirectionStatus.paused,
        ),
        const Direction(
          id: 'p1',
          name: 'Пауза 1',
          order: 1,
          status: DirectionStatus.paused,
        ),
        const Direction(
          id: 'z2',
          name: 'Закрыто 2',
          order: 2,
          status: DirectionStatus.done,
        ),
        const Direction(
          id: 'z1',
          name: 'Закрыто 1',
          order: 1,
          status: DirectionStatus.done,
        ),
      ];
      final milestones = [
        const Milestone(id: 'm3', directionId: 'd1', title: 'Веха 3', order: 3),
        const Milestone(id: 'm1', directionId: 'd1', title: 'Веха 1', order: 1),
        const Milestone(id: 'm2', directionId: 'd1', title: 'Веха 2', order: 2),
      ];
      final md = serializeCourse(directions, milestones);

      // Активные направления упорядочены по order
      final firstIdx = md.indexOf('### 1. Первое');
      final secondIdx = md.indexOf('### 2. Второе');
      final thirdIdx = md.indexOf('### 3. Третье');
      expect(firstIdx, isNonNegative);
      expect(secondIdx, greaterThan(firstIdx));
      expect(thirdIdx, greaterThan(secondIdx));

      // Вехи направления d1 упорядочены по order
      final m1Idx = md.indexOf('- [ ] Веха 1');
      final m2Idx = md.indexOf('- [ ] Веха 2');
      final m3Idx = md.indexOf('- [ ] Веха 3');
      expect(m1Idx, isNonNegative);
      expect(m2Idx, greaterThan(m1Idx));
      expect(m3Idx, greaterThan(m2Idx));

      // Направления на паузе упорядочены по order
      final p1Idx = md.indexOf('### Пауза 1 — веха 0 из 0');
      final p2Idx = md.indexOf('### Пауза 2 — веха 0 из 0');
      expect(p1Idx, isNonNegative);
      expect(p2Idx, greaterThan(p1Idx));

      // Закрытые направления упорядочены по order
      final z1Idx = md.indexOf('### Закрыто 1 — 0 из 0');
      final z2Idx = md.indexOf('### Закрыто 2 — 0 из 0');
      expect(z1Idx, isNonNegative);
      expect(z2Idx, greaterThan(z1Idx));
    });

    test('доказательства попадают в Курс.md с отступом, пустой список не даёт лишних строк', () {
      final directions = [
        const Direction(id: 'd1', name: 'Продукт', order: 1),
      ];
      final milestones = [
        const Milestone(
          id: 'm1',
          directionId: 'd1',
          title: 'Бот отвечает на 3 команды в проде',
          order: 1,
          doneSprint: '2026-W37',
          proofs: [
            '✅ 16.09 Написать обработчик /start #проекты',
            '✅ 17.09 Выкатить на прод #проекты',
          ],
        ),
        const Milestone(
          id: 'm2',
          directionId: 'd1',
          title: 'Открытая веха без доказательств',
          order: 2,
        ),
        const Milestone(
          id: 'm3',
          directionId: 'd1',
          title: 'Открытая веха с доказательствами',
          order: 3,
          proofs: [
            '✅ 18.09 Первое доказательство #проекты',
          ],
        ),
      ];

      final md = serializeCourse(directions, milestones);

      expect(
        md,
        contains(
          '- [x] Бот отвечает на 3 команды в проде `2026-W37`\n'
          '  - ✅ 16.09 Написать обработчик /start #проекты\n'
          '  - ✅ 17.09 Выкатить на прод #проекты\n',
        ),
      );
      expect(
        md,
        contains(
          '- [ ] Открытая веха без доказательств\n'
          '- [ ] Открытая веха с доказательствами\n'
          '  - ✅ 18.09 Первое доказательство #проекты\n',
        ),
      );
      expect(md, isNot(contains('  - \n')));
    });
  });

  test('веха недели из лестницы попадает в зеркало спринта текстом', () {
    // У недели, взявшей ступень лестницы, sprint.milestone пуст: там только
    // ссылка. Без разворачивания Спринты/*.md терял веху целиком.
    final sprint = Sprint(
      id: '2026-W29',
      start: DateTime(2026, 7, 13),
      goal: 40,
      milestoneId: 'm1',
    );
    final content = serializeSprint(
      sprint,
      const [],
      milestoneText: 'Бот отвечает на 3 команды в проде',
    );
    expect(content, contains('веха: Бот отвечает на 3 команды в проде'));
    expect(content, contains('**Веха:** Бот отвечает на 3 команды в проде'));

    // Свободный текст старых недель работает как раньше.
    final old = Sprint(
      id: '2026-W28',
      start: DateTime(2026, 7, 6),
      goal: 40,
      milestone: 'Старая веха',
    );
    expect(serializeSprint(old, const []), contains('веха: Старая веха'));
  });
}
