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
}
