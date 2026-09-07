import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_task.dart';

PomoTask _t(int minutes) =>
    PomoTask(description: 'x', category: 'c', durationMinutes: minutes);

void main() {
  // classic: помидор 25, короткий 5, длинный 15 каждые 4, лимит сессии 3ч.
  List<TaskSession> split(List<PomoTask> tasks) => sessionSplit(
    tasks,
    pomodoroMinutes: 25,
    shortBreak: 5,
    longBreak: 15,
    longEvery: 4,
    limitMinutes: 180,
  );

  test('стоимость по стене = помидоры + перерывы между ними', () {
    // 3 помидора: 25 + (5+25) + (5+25) = 85.
    expect(split([_t(60)]).single.wallMinutes, 85);
  });

  test('новая сессия открывается, когда задача не влезает в лимит', () {
    // 55 + 60 = 115 ≤ 180 — вместе; +100 = 215 > 180 — третья в новую сессию.
    final marks = split([_t(50), _t(50), _t(75)]);
    expect(marks.map((m) => m.session).toList(), [0, 0, 1]);
    expect(marks.map((m) => m.wallMinutes).toList(), [55, 60, 100]);
  });

  test('задача длиннее лимита занимает свою сессию одна, а не создаёт пустую', () {
    final marks = split([_t(600), _t(25)]);
    expect(marks.map((m) => m.session).toList(), [0, 1]);
  });

  test('длинный перерыв на границе серии удлиняет стену', () {
    // 5 помидоров: 25 +30 +30 +30 + (15+25) = 155 (5-й перерыв длинный).
    expect(split([_t(125)]).single.wallMinutes, 155);
  });

  group('расписание сессий', () {
    test('parseSessionWindows: разбор, отсев кривых, сортировка', () {
      expect(parseSessionWindows(['10:00-13:00', '13:00-15:00']), [
        (start: 600, end: 780),
        (start: 780, end: 900),
      ]);
      expect(
        parseSessionWindows(['мусор', '25:00-26:00', '13:00-10:00', '']),
        isEmpty,
      );
      expect(
        parseSessionWindows(['13:00-15:00', '10:00-13:00']).first.start,
        600,
      );
    });

    test('окна задают вместимость сессии вместо длины', () {
      final marks = sessionSplit(
        [_t(50), _t(50), _t(75), _t(25)],
        pomodoroMinutes: 25,
        shortBreak: 5,
        longBreak: 15,
        longEvery: 4,
        limitMinutes: 180,
        windows: parseSessionWindows(['10:00-13:00', '13:00-15:00']),
      );
      // окно 0 (180 мин): 55+60=115, +100 не влезает → окно 1 (120 мин):
      // 100, +30 не влезает → сессия 2 (за расписанием, лимит 180).
      expect(marks.map((m) => m.session).toList(), [0, 0, 1, 2]);
    });
  });
}
