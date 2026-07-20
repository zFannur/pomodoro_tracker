import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';

Map<String, dynamic> decode(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

Map<String, dynamic> task(String id) => {
  'id': id,
  'desc': id,
  'cat': 'x',
  'min': 25,
};

Map<String, dynamic> session(String id, String time) => {
  'id': id,
  't': time,
  'm': 25,
  'c': 'x',
  'd': id,
};

String doc({
  List<Map<String, dynamic>> todo = const [],
  List<Map<String, dynamic>> planner = const [],
  Map<String, dynamic> days = const {},
  Map<String, dynamic> sprints = const {},
  Map<String, dynamic> graves = const {},
  Map<String, dynamic> rollover = const {},
  Map<String, dynamic> extra = const {},
}) => jsonEncode({
  'schema': 2,
  'todo': todo,
  'planner': planner,
  'days': days,
  'sprints': sprints,
  'graves': graves,
  'rollover': rollover,
  ...extra,
});

List<String> ids(Object? raw) => [
  for (final e in raw as List) (e as Map<String, dynamic>)['id'] as String,
];

void main() {
  test('локального снимка нет — удалённый возвращается дословно', () {
    final remote = doc(todo: [task('a')]);
    expect(mergeData(null, remote, localWins: true), remote);
    expect(mergeData('  ', remote, localWins: false), remote);
  });

  test('задачи объединяются по id, ничего не теряется', () {
    final merged = decode(
      mergeData(
        doc(todo: [task('a'), task('b')]),
        doc(todo: [task('b'), task('c')]),
        localWins: true,
      ),
    );
    expect(ids(merged['todo']), ['a', 'b', 'c']);
  });

  test('помидоры с двух устройств за один день сливаются и сортируются', () {
    final merged = decode(
      mergeData(
        doc(days: {
          '2026-07-20': {
            'goal': 8,
            's': [session('p1', '09:00'), session('p3', '15:00')],
          },
        }),
        doc(days: {
          '2026-07-20': {
            'goal': 8,
            's': [session('p2', '12:00')],
          },
        }),
        localWins: true,
      ),
    );
    final day = merged['days']['2026-07-20'] as Map<String, dynamic>;
    // Ни один помидор не потерян, порядок восстановлен по времени.
    expect(ids(day['s']), ['p1', 'p2', 'p3']);
  });

  test('день, которого нет у победителя, приезжает целиком', () {
    final merged = decode(
      mergeData(
        doc(days: {
          '2026-07-20': {
            'goal': 8,
            's': [session('p1', '09:00')],
          },
        }),
        doc(days: {
          '2026-07-19': {
            'goal': 8,
            's': [session('old', '10:00')],
          },
        }),
        localWins: true,
      ),
    );
    expect((merged['days'] as Map).keys.toSet(), {'2026-07-19', '2026-07-20'});
  });

  test('удаление побеждает и не зависит от того, чья сторона выиграла', () {
    for (final localWins in [true, false]) {
      final merged = decode(
        mergeData(
          // Локально задача удалена — есть надгробие.
          doc(todo: [task('b')], graves: {'a': '2026-07-20T10:00:00.000Z'}),
          // Удалённо она же жива и даже отредактирована.
          doc(todo: [{...task('a'), 'desc': 'правка'}, task('b')]),
          localWins: localWins,
        ),
      );
      expect(ids(merged['todo']), ['b'], reason: 'localWins=$localWins');
    }
  });

  test('надгробие вычищает и запись журнала', () {
    final merged = decode(
      mergeData(
        doc(graves: {'p1': '2026-07-20T10:00:00.000Z'}),
        doc(days: {
          '2026-07-20': {
            's': [session('p1', '09:00'), session('p2', '12:00')],
          },
        }),
        localWins: true,
      ),
    );
    final day = merged['days']['2026-07-20'] as Map<String, dynamic>;
    expect(ids(day['s']), ['p2']);
  });

  test('незнакомые ключи верхнего уровня выживают', () {
    // Прямая защита от старой ошибки mergeTasksJson: он пересобирал
    // результат из известных ключей и молча терял всё остальное.
    final merged = decode(
      mergeData(
        doc(extra: {'будущаяСекция': 42}),
        doc(),
        localWins: true,
      ),
    );
    expect(merged['будущаяСекция'], 42);
    expect(merged['schema'], 2);
  });

  test('скаляры разрешаются по localWins', () {
    Object? goalWhen({required bool localWins}) => decode(
      mergeData(
        doc(days: {'2026-07-20': {'goal': 10, 's': <Object>[]}}),
        doc(days: {'2026-07-20': {'goal': 3, 's': <Object>[]}}),
        localWins: localWins,
      ),
    )['days']['2026-07-20']['goal'];

    expect(goalWhen(localWins: true), 10);
    expect(goalWhen(localWins: false), 3);
  });

  test('веха спринта — скаляр, «сделано» объединяется', () {
    final merged = decode(
      mergeData(
        doc(sprints: {
          '2026-W30': {'goal': 40, 'milestone': 'моя', 'done': ['✅ a']},
        }),
        doc(sprints: {
          '2026-W30': {'goal': 50, 'milestone': 'чужая', 'done': ['✅ b']},
        }),
        localWins: true,
      ),
    );
    final sprint = merged['sprints']['2026-W30'] as Map<String, dynamic>;
    expect(sprint['milestone'], 'моя');
    expect(sprint['goal'], 40);
    expect(sprint['done'], ['✅ a', '✅ b']);
  });

  test('заметки дня объединяются без дублей', () {
    final merged = decode(
      mergeData(
        doc(days: {
          '2026-07-20': {'s': <Object>[], 'n': ['09:00 — раз', '10:00 — два']},
        }),
        doc(days: {
          '2026-07-20': {'s': <Object>[], 'n': ['10:00 — два', '11:00 — три']},
        }),
        localWins: true,
      ),
    );
    expect(merged['days']['2026-07-20']['n'], [
      '09:00 — раз',
      '10:00 — два',
      '11:00 — три',
    ]);
  });

  test('надгробия объединяются, время берётся более позднее', () {
    final merged = decode(
      mergeData(
        doc(graves: {'a': '2026-07-20T10:00:00.000Z'}),
        doc(graves: {
          'a': '2026-07-20T18:00:00.000Z',
          'b': '2026-07-19T10:00:00.000Z',
        }),
        localWins: true,
      ),
    );
    expect(merged['graves'], {
      'a': '2026-07-20T18:00:00.000Z',
      'b': '2026-07-19T10:00:00.000Z',
    });
  });

  test('rollover — максимум строк, а не выбор победителя', () {
    // Устройство, не запускавшееся три дня, не должно откатить отметку и
    // повторно сбросить лягушку, уже выбранную сегодня на другом.
    final merged = decode(
      mergeData(
        doc(rollover: {'day': '2026-07-17', 'week': '2026-W29'}),
        doc(rollover: {'day': '2026-07-20', 'week': '2026-W30'}),
        localWins: true,
      ),
    );
    expect(merged['rollover'], {'day': '2026-07-20', 'week': '2026-W30'});
  });

  test('идемпотентность: повторное слияние ничего не меняет', () {
    // Без этого два устройства могут бесконечно пинговать файл друг другу —
    // глазами такое не ловится, только тестом.
    final local = doc(
      todo: [task('a')],
      days: {
        '2026-07-20': {
          'goal': 8,
          's': [session('p1', '09:00')],
          'n': ['09:00 — раз'],
        },
      },
      graves: {'x': '2026-07-20T10:00:00.000Z'},
    );
    final remote = doc(
      todo: [task('b')],
      days: {
        '2026-07-20': {
          'goal': 8,
          's': [session('p2', '12:00')],
          'n': ['10:00 — два'],
        },
      },
    );
    final once = mergeData(local, remote, localWins: true);
    expect(mergeData(once, remote, localWins: true), once);
    expect(mergeData(once, once, localWins: true), once);
  });

  test('битый локальный файл не мешает забрать удалённый', () {
    final remote = doc(todo: [task('a')]);
    expect(mergeData('{не json', remote, localWins: true), remote);
  });
}
