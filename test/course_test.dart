import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';

void main() {
  Direction dir(
    String id, {
    String name = '',
    int order = 0,
    List<String> categories = const [],
    DirectionStatus status = DirectionStatus.active,
    DateTime? horizon,
    String note = '',
  }) => Direction(
    id: id,
    name: name.isEmpty ? id : name,
    order: order,
    categories: categories,
    status: status,
    horizon: horizon,
    note: note,
  );

  Milestone mile(
    String id,
    String directionId, {
    String title = '',
    int order = 0,
    String doneSprint = '',
    DateTime? doneAt,
  }) => Milestone(
    id: id,
    directionId: directionId,
    title: title.isEmpty ? id : title,
    order: order,
    doneSprint: doneSprint,
    doneAt: doneAt,
  );

  PomoSession session(String id, String category) => PomoSession(
    id: id,
    start: DateTime(2026, 7, 20, 10),
    minutes: 25,
    category: category,
    task: 'task $id',
  );

  DayLog day(DateTime date, List<PomoSession> sessions) =>
      DayLog(date: date, goal: 8, sessions: sessions);

  group('categoryIndex', () {
    test('категория в одном направлении индексируется', () {
      final directions = [
        dir('d1', categories: ['код', 'архитектура']),
      ];
      final index = categoryIndex(directions);
      expect(index['код'], 'd1');
      expect(index['архитектура'], 'd1');
      expect(index['спорт'], isNull);
    });

    test('категория в двух направлениях достаётся первому по order', () {
      final directions = [
        dir('d2', order: 2, categories: ['общая']),
        dir('d1', order: 1, categories: ['общая']),
      ];
      final index = categoryIndex(directions);
      expect(index['общая'], 'd1');
    });

    test('при одинаковом order побеждает первое направление в списке', () {
      final directions = [
        dir('d1', order: 0, categories: ['общая']),
        dir('d2', order: 0, categories: ['общая']),
      ];
      final index = categoryIndex(directions);
      expect(index['общая'], 'd1');
    });
  });

  group('ladder и nextOpen', () {
    test('ladder возвращает вехи направления по возрастанию order', () {
      final all = [
        mile('m3', 'd1', order: 3),
        mile('m1', 'd1', order: 1),
        mile('other', 'd2', order: 0),
        mile('m2', 'd1', order: 2),
      ];
      final result = ladder(all, 'd1');
      expect(result.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);
    });

    test('ladder возвращает пустой список если вех направления нет', () {
      expect(ladder([], 'd1'), isEmpty);
    });

    test('nextOpen возвращает первую незакрытую ступень по order', () {
      final all = [
        mile('m1', 'd1', order: 1, doneSprint: '2026-W28'),
        mile('m2', 'd1', order: 2),
        mile('m3', 'd1', order: 3),
      ];
      expect(nextOpen(all, 'd1')?.id, 'm2');
    });

    test('nextOpen пропускает закрытые вехи', () {
      final all = [
        mile('m1', 'd1', order: 1, doneSprint: '2026-W28'),
        mile('m2', 'd1', order: 2, doneSprint: '2026-W29'),
        mile('m3', 'd1', order: 3),
      ];
      expect(nextOpen(all, 'd1')?.id, 'm3');
    });

    test('nextOpen возвращает null на пройденной лестнице', () {
      final all = [
        mile('m1', 'd1', order: 1, doneSprint: '2026-W28'),
        mile('m2', 'd1', order: 2, doneSprint: '2026-W29'),
      ];
      expect(nextOpen(all, 'd1'), isNull);
    });

    test('nextOpen возвращает null если вех нет вообще', () {
      expect(nextOpen([], 'd1'), isNull);
    });
  });

  group('closureRate', () {
    final now = DateTime(2026, 8, 1, 12);

    test('0 без закрытий', () {
      final all = [
        mile('m1', 'd1', order: 1),
        mile('m2', 'd1', order: 2),
      ];
      expect(closureRate(all, 'd1', now), 0.0);
    });

    test('закрытия старше окна не считаются', () {
      // Окно 84 дня: закрытие 90 дней назад не должно учитываться
      final all = [
        mile(
          'old',
          'd1',
          order: 1,
          doneSprint: '2026-W10',
          doneAt: now.subtract(const Duration(days: 90)),
        ),
      ];
      expect(closureRate(all, 'd1', now, days: 84), 0.0);
    });

    test('закрытия в будущем не считаются', () {
      final all = [
        mile(
          'future',
          'd1',
          order: 1,
          doneSprint: '2026-W35',
          doneAt: now.add(const Duration(days: 5)),
        ),
      ];
      expect(closureRate(all, 'd1', now), 0.0);
    });

    test('вехи других направлений не влияют на темп', () {
      final all = [
        mile(
          'other',
          'd2',
          order: 1,
          doneSprint: '2026-W30',
          doneAt: now.subtract(const Duration(days: 10)),
        ),
      ];
      expect(closureRate(all, 'd1', now), 0.0);
    });

    test('рассчитывает темп за 30 дней по закрытиям в окне', () {
      // 1 закрытие за 30 дней -> rate = 1.0
      final all = [
        mile(
          'm1',
          'd1',
          order: 1,
          doneSprint: '2026-W30',
          doneAt: now.subtract(const Duration(days: 10)),
        ),
      ];
      expect(closureRate(all, 'd1', now, days: 30), 1.0);
    });
  });

  group('directionEta', () {
    final now = DateTime(2026, 8, 1, 12);

    test('null без темпа (0 закрытий)', () {
      final all = [
        mile('m1', 'd1', order: 1),
      ];
      expect(directionEta(all, 'd1', now), isNull);
    });

    test('null на пройденной лестнице (нет открытых вех)', () {
      final all = [
        mile(
          'm1',
          'd1',
          order: 1,
          doneSprint: '2026-W30',
          doneAt: now.subtract(const Duration(days: 10)),
        ),
      ];
      expect(directionEta(all, 'd1', now), isNull);
    });

    test('при темпе 1 веха / 30 дней и трёх открытых вехах — примерно +90 дней', () {
      // 1 закрытие за 30 дней -> rate = 1.0 веха / 30 дней.
      // 3 открытых вехи -> прогноз +90 дней.
      final all = [
        mile(
          'm0',
          'd1',
          order: 0,
          doneSprint: '2026-W30',
          doneAt: now.subtract(const Duration(days: 10)),
        ),
        mile('m1', 'd1', order: 1),
        mile('m2', 'd1', order: 2),
        mile('m3', 'd1', order: 3),
      ];
      final eta = directionEta(all, 'd1', now, days: 30);
      expect(eta, isNotNull);
      expect(eta!.difference(now).inDays, 90);
    });
  });

  group('pomosByDirection', () {
    test('помидоры разносятся по направлениям через категории', () {
      final directions = [
        dir('work', categories: ['работа', 'код']),
        dir('health', categories: ['спорт']),
      ];
      final days = [
        day(DateTime(2026, 7, 20), [
          session('s1', 'работа'),
          session('s2', 'код'),
          session('s3', 'спорт'),
        ]),
      ];
      final result = pomosByDirection(days, directions);
      expect(result['work'], 2);
      expect(result['health'], 1);
      expect(result[''], 0);
    });

    test('помидор с чужой категорией попадает в ключ «»', () {
      final directions = [
        dir('work', categories: ['работа']),
      ];
      final days = [
        day(DateTime(2026, 7, 20), [
          session('s1', 'работа'),
          session('s2', 'неизвестная'),
        ]),
      ];
      final result = pomosByDirection(days, directions);
      expect(result['work'], 1);
      expect(result[''], 1);
    });

    test('пустые дни возвращают нули по всем направлениям', () {
      final directions = [dir('work')];
      final result = pomosByDirection([], directions);
      expect(result['work'], 0);
      expect(result[''], 0);
    });
  });

  group('closuresByWeek', () {
    test('группировка по id недели', () {
      final all = [
        mile('m1', 'd1', doneSprint: '2026-W28'),
        mile('m2', 'd1', doneSprint: '2026-W29'),
        mile('m3', 'd2', doneSprint: '2026-W29'),
        mile('open', 'd1'), // открытая
      ];
      final result = closuresByWeek(all);
      expect(result.keys.toSet(), {'2026-W28', '2026-W29'});
      expect(result['2026-W28']?.map((m) => m.id).toList(), ['m1']);
      expect(result['2026-W29']?.map((m) => m.id).toList(), ['m2', 'm3']);
    });

    test('открытые вехи не попадают в ленту', () {
      final all = [
        mile('open1', 'd1'),
        mile('open2', 'd2'),
      ];
      final result = closuresByWeek(all);
      expect(result, isEmpty);
    });
  });

  group('Direction and Milestone copyWith and props', () {
    test('Direction.copyWith с clearHorizon', () {
      final d = dir('d1', horizon: DateTime(2026, 12, 1));
      expect(d.horizon, isNotNull);
      final cleared = d.copyWith(clearHorizon: true);
      expect(cleared.horizon, isNull);
    });

    test('Milestone.copyWith с reopen', () {
      final m = mile('m1', 'd1', doneSprint: '2026-W29', doneAt: DateTime.now());
      expect(m.done, isTrue);
      final reopened = m.copyWith(reopen: true);
      expect(reopened.done, isFalse);
      expect(reopened.doneSprint, isEmpty);
      expect(reopened.doneAt, isNull);
    });
  });
}
