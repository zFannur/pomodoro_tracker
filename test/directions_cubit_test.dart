import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';

/// Фейковый репозиторий курса в памяти для изолированного тестирования [DirectionsCubit].
class FakeDirectionRepository implements DirectionRepository {
  Course _course = (directions: const [], milestones: const []);
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<Either<Failure, Course>> loadCourse() async {
    if (failLoad) {
      return Either.left(const StorageFailure('ошибка загрузки курса'));
    }
    return Either.right((
      directions: [..._course.directions],
      milestones: [..._course.milestones],
    ));
  }

  @override
  Future<Either<Failure, Unit>> saveCourse(Course course) async {
    if (failSave) {
      return Either.left(const StorageFailure('ошибка сохранения курса'));
    }
    _course = (
      directions: [...course.directions],
      milestones: [...course.milestones],
    );
    return Either.right(unit);
  }
}

void main() {
  late FakeDirectionRepository repo;
  late DirectionsCubit cubit;

  setUp(() async {
    repo = FakeDirectionRepository();
    cubit = DirectionsCubit(repo);
    await cubit.refresh();
  });

  tearDown(() async {
    await cubit.close();
  });

  test('начальное состояние — loading, после refresh — ready и пусто', () async {
    final freshRepo = FakeDirectionRepository();
    final freshCubit = DirectionsCubit(freshRepo);
    expect(freshCubit.state.status, DirectionsStatus.loading);
    await freshCubit.refresh();
    expect(freshCubit.state.status, DirectionsStatus.ready);
    expect(freshCubit.state.directions, isEmpty);
    expect(freshCubit.state.milestones, isEmpty);
    await freshCubit.close();
  });

  test('добавление направления и вехи, порядок order', () async {
    await cubit.addDirection(' Цели на год ');
    expect(cubit.state.directions.length, 1);
    final dir1 = cubit.state.directions.first;
    expect(dir1.name, 'Цели на год');
    expect(dir1.order, 0);
    expect(dir1.status, DirectionStatus.active);
    expect(dir1.id, isNotEmpty);

    await cubit.addDirection('Здоровье');
    expect(cubit.state.directions.length, 2);
    final dir2 = cubit.state.directions.last;
    expect(dir2.name, 'Здоровье');
    expect(dir2.order, 1);

    // Добавляем вехи к первому направлению
    await cubit.addMilestone(dir1.id, ' Веха 1.1 ');
    expect(cubit.state.milestones.length, 1);
    final m1 = cubit.state.milestones.first;
    expect(m1.title, 'Веха 1.1');
    expect(m1.directionId, dir1.id);
    expect(m1.order, 0);

    await cubit.addMilestone(dir1.id, 'Веха 1.2');
    expect(cubit.state.milestones.length, 2);
    final m2 = cubit.state.milestones.last;
    expect(m2.title, 'Веха 1.2');
    expect(m2.order, 1);

    // Веха второго направления начинает order внутри своего направления с 0
    await cubit.addMilestone(dir2.id, 'Веха 2.1');
    expect(cubit.state.milestones.length, 3);
    final m3 = cubit.state.milestones.last;
    expect(m3.directionId, dir2.id);
    expect(m3.order, 0);

    // Проверяем фиксацию данных в репозитории
    final saved = await repo.loadCourse();
    expect(saved.isRight(), isTrue);
    saved.match(
      (_) => fail('Не должно быть ошибки'),
      (course) {
        expect(course.directions.length, 2);
        expect(course.milestones.length, 3);
      },
    );
  });

  test('reorderMilestones перенумеровывает подряд', () async {
    await cubit.addDirection('Разработка');
    final dirId = cubit.state.directions.first.id;

    await cubit.addMilestone(dirId, 'Ступень 0');
    await cubit.addMilestone(dirId, 'Ступень 1');
    await cubit.addMilestone(dirId, 'Ступень 2');

    final initialLadder = ladder(cubit.state.milestones, dirId);
    expect(initialLadder.map((m) => m.title).toList(), [
      'Ступень 0',
      'Ступень 1',
      'Ступень 2',
    ]);
    expect(initialLadder.map((m) => m.order).toList(), [0, 1, 2]);

    // Перемещаем элемент 0 в конец (индекс 2)
    await cubit.reorderMilestones(dirId, 0, 2);

    final reorderedLadder = ladder(cubit.state.milestones, dirId);
    expect(reorderedLadder.map((m) => m.title).toList(), [
      'Ступень 1',
      'Ступень 2',
      'Ступень 0',
    ]);
    // Порядковые номера обязаны идти строго подряд 0, 1, 2
    expect(reorderedLadder.map((m) => m.order).toList(), [0, 1, 2]);
  });

  test('reorderDirections перенумеровывает подряд', () async {
    await cubit.addDirection('Д1');
    await cubit.addDirection('Д2');
    await cubit.addDirection('Д3');

    // Перемещаем первое направление на последнюю позицию
    await cubit.reorderDirections(0, 2);

    final list = cubit.state.active;
    expect(list.map((d) => d.name).toList(), ['Д2', 'Д3', 'Д1']);
    expect(list.map((d) => d.order).toList(), [0, 1, 2]);
  });

  test('closeMilestone -> nextOpen отдаёт следующую', () async {
    await cubit.addDirection('Проект');
    final dirId = cubit.state.directions.first.id;

    await cubit.addMilestone(dirId, 'Шаг 1');
    await cubit.addMilestone(dirId, 'Шаг 2');

    final m1 = cubit.state.milestones[0];
    final m2 = cubit.state.milestones[1];

    // Изначально следующая открытая — Шаг 1
    expect(cubit.state.next(dirId)?.id, m1.id);

    final closedAt = DateTime(2026, 7, 25, 14, 30);
    await cubit.closeMilestone(m1.id, '2026-W30', closedAt);

    // Теперь следующая открытая — Шаг 2
    expect(cubit.state.next(dirId)?.id, m2.id);
    final closedM1 = cubit.state.milestoneById(m1.id);
    expect(closedM1?.done, isTrue);
    expect(closedM1?.doneSprint, '2026-W30');
    expect(closedM1?.doneAt, closedAt);

    // Закрываем и Шаг 2 — лестница пройдена, next отдаёт null
    await cubit.closeMilestone(m2.id, '2026-W30', closedAt);
    expect(cubit.state.next(dirId), isNull);

    // Открываем Шаг 1 заново — он снова становится открытым
    await cubit.reopenMilestone(m1.id);
    final reopenedM1 = cubit.state.milestoneById(m1.id);
    expect(reopenedM1?.done, isFalse);
    expect(reopenedM1?.doneSprint, isEmpty);
    expect(reopenedM1?.doneAt, isNull);
    expect(cubit.state.next(dirId)?.id, m1.id);
  });

  test('deleteDirection уносит и вехи направления', () async {
    await cubit.addDirection('Направление А');
    await cubit.addDirection('Направление Б');

    final dirA = cubit.state.directions.first;
    final dirB = cubit.state.directions.last;

    await cubit.addMilestone(dirA.id, 'Веха А1');
    await cubit.addMilestone(dirA.id, 'Веха А2');
    await cubit.addMilestone(dirB.id, 'Веха Б1');

    expect(cubit.state.directions.length, 2);
    expect(cubit.state.milestones.length, 3);

    // Удаляем направление А
    await cubit.deleteDirection(dirA.id);

    expect(cubit.state.directions.map((d) => d.id).toList(), [dirB.id]);
    expect(cubit.state.milestones.map((m) => m.directionId).toList(), [dirB.id]);
    expect(cubit.state.milestones.first.title, 'Веха Б1');
  });

  test('progress считает закрытые/всего', () async {
    await cubit.addDirection('Фитнес');
    final dirId = cubit.state.directions.first.id;

    expect(cubit.state.progress(dirId), (done: 0, total: 0));

    await cubit.addMilestone(dirId, 'Веха 1');
    await cubit.addMilestone(dirId, 'Веха 2');
    await cubit.addMilestone(dirId, 'Веха 3');

    expect(cubit.state.progress(dirId), (done: 0, total: 3));

    final m1 = cubit.state.milestones[0];
    final m2 = cubit.state.milestones[1];

    await cubit.closeMilestone(m1.id, '2026-W30', DateTime.now());
    expect(cubit.state.progress(dirId), (done: 1, total: 3));

    await cubit.closeMilestone(m2.id, '2026-W30', DateTime.now());
    expect(cubit.state.progress(dirId), (done: 2, total: 3));

    await cubit.deleteMilestone(m1.id);
    expect(cubit.state.progress(dirId), (done: 1, total: 2));
  });

  test('setStatus управляет активностью, геттеры active, paused, finished', () async {
    await cubit.addDirection('Активное');
    await cubit.addDirection('На паузе');
    await cubit.addDirection('Завершённое');

    final d1 = cubit.state.directions[0];
    final d2 = cubit.state.directions[1];
    final d3 = cubit.state.directions[2];

    await cubit.setStatus(d2.id, DirectionStatus.paused);
    await cubit.setStatus(d3.id, DirectionStatus.done);

    expect(cubit.state.active.map((d) => d.id).toList(), [d1.id]);
    expect(cubit.state.paused.map((d) => d.id).toList(), [d2.id]);
    expect(cubit.state.finished.map((d) => d.id).toList(), [d3.id]);
  });

  test('updateDirection и updateMilestone обновляют данные', () async {
    await cubit.addDirection('Старое имя');
    final dir = cubit.state.directions.first;

    final updatedDir = dir.copyWith(
      name: 'Новое имя',
      note: 'Obsidian Note',
      categories: ['работа', 'бизнес'],
    );
    await cubit.updateDirection(updatedDir);

    final storedDir = cubit.state.directions.first;
    expect(storedDir.name, 'Новое имя');
    expect(storedDir.note, 'Obsidian Note');
    expect(storedDir.categories, ['работа', 'бизнес']);

    await cubit.addMilestone(storedDir.id, 'Старая веха');
    final m = cubit.state.milestones.first;
    final updatedM = m.copyWith(title: 'Новая веха');
    await cubit.updateMilestone(updatedM);

    expect(cubit.state.milestones.first.title, 'Новая веха');
  });

  test('поиск: milestoneById, directionOf, directionForCategory', () async {
    await cubit.addDirection('Проект А');
    final dirA = cubit.state.directions.first;
    await cubit.updateDirection(dirA.copyWith(categories: ['кодинг', 'архитектура']));

    await cubit.addMilestone(dirA.id, 'Веха А1');
    final m = cubit.state.milestones.first;

    expect(cubit.state.milestoneById(m.id)?.id, m.id);
    expect(cubit.state.milestoneById('non-existent'), isNull);

    expect(cubit.state.directionOf(m)?.id, dirA.id);

    expect(cubit.state.directionForCategory('кодинг')?.id, dirA.id);
    expect(cubit.state.directionForCategory('неизвестное'), isNull);
  });

  test('closuresByWeekMap собирает вехи по неделям закрытия', () async {
    await cubit.addDirection('План');
    final dirId = cubit.state.directions.first.id;

    await cubit.addMilestone(dirId, 'В1');
    await cubit.addMilestone(dirId, 'В2');
    await cubit.addMilestone(dirId, 'В3');

    final m1 = cubit.state.milestones[0];
    final m2 = cubit.state.milestones[1];
    final m3 = cubit.state.milestones[2];

    final now = DateTime(2026, 7, 20);
    await cubit.closeMilestone(m1.id, '2026-W29', now);
    await cubit.closeMilestone(m2.id, '2026-W30', now);
    await cubit.closeMilestone(m3.id, '2026-W30', now);

    final map = cubit.state.closuresByWeekMap;
    expect(map['2026-W29']?.length, 1);
    expect(map['2026-W29']?.first.id, m1.id);
    expect(map['2026-W30']?.length, 2);
    expect(map['2026-W30']?.map((m) => m.id).toList(), [m2.id, m3.id]);
  });

  test('ошибка загрузки и сохранения выставляет статус failure', () async {
    repo.failLoad = true;
    await cubit.refresh();
    expect(cubit.state.status, DirectionsStatus.failure);
    expect(cubit.state.error, 'ошибка загрузки курса');

    repo.failLoad = false;
    await cubit.refresh();
    expect(cubit.state.status, DirectionsStatus.ready);

    repo.failSave = true;
    await cubit.addDirection('Тест ошибки');
    expect(cubit.state.status, DirectionsStatus.failure);
    expect(cubit.state.error, 'ошибка сохранения курса');
  });

  test('addProof добавляет доказательство, не дублирует строку, игнорирует пустой id и несуществующую веху', () async {
    await cubit.addDirection('Разработка');
    final dirId = cubit.state.directions.first.id;
    await cubit.addMilestone(dirId, 'Ступень 1');
    final m1 = cubit.state.milestones.first;

    const proof1 = '✅ 16.09 Сделать фичу #код';
    await cubit.addProof(m1.id, proof1);

    expect(cubit.state.milestoneById(m1.id)?.proofs, [proof1]);

    // Повторное добавление той же строки не дублирует
    await cubit.addProof(m1.id, proof1);
    expect(cubit.state.milestoneById(m1.id)?.proofs, [proof1]);

    // Добавление второй уникальной строки
    const proof2 = '✅ 17.09 Написать тесты #тесты';
    await cubit.addProof(m1.id, proof2);
    expect(cubit.state.milestoneById(m1.id)?.proofs, [proof1, proof2]);

    // Пустой id — тихо ничего не делает
    await cubit.addProof('', '✅ 18.09 Что-то #прочее');
    expect(cubit.state.milestoneById(m1.id)?.proofs, [proof1, proof2]);

    // Несуществующая веха — тихо ничего не делает
    await cubit.addProof('non-existent', '✅ 19.09 Что-то #прочее');
    expect(cubit.state.milestones.length, 1);
    expect(cubit.state.milestones.first.proofs, [proof1, proof2]);
  });
}
