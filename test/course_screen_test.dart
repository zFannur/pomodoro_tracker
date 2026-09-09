import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/core/failure.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';
import 'package:pomodoro_tracker/domain/entities/direction.dart';
import 'package:pomodoro_tracker/domain/entities/pomo_session.dart';
import 'package:pomodoro_tracker/domain/repositories.dart';
import 'package:pomodoro_tracker/presentation/cubits/directions_cubit.dart';
import 'package:pomodoro_tracker/presentation/cubits/settings_cubit.dart';
import 'package:pomodoro_tracker/presentation/screens/course_screen.dart';

/// Фейковый репозиторий курса в памяти для тестирования [CourseScreen].
class _MemCourseRepo implements DirectionRepository {
  _MemCourseRepo(this._course);

  Course _course;

  @override
  Future<Either<Failure, Course>> loadCourse() async => Either.right((
        directions: [..._course.directions],
        milestones: [..._course.milestones],
      ));

  @override
  Future<Either<Failure, Unit>> saveCourse(Course course) async {
    _course = (
      directions: [...course.directions],
      milestones: [...course.milestones],
    );
    return Either.right(unit);
  }
}

/// Фейковый репозиторий настроек в памяти.
class _MemSettingsRepo implements SettingsRepository {
  @override
  Future<Either<Failure, AppSettings>> load() async =>
      Either.right(AppSettings.fromJson(const {}, fallbackPath: '.'));

  @override
  Future<Either<Failure, Unit>> save(AppSettings settings) async =>
      Either.right(unit);
}

/// Журнал в памяти за последние дни для проверки бюджета внимания и ленты закрытий.
class _MemJournal implements JournalRepository {
  @override
  Future<Either<Failure, Unit>> addSession(PomoSession s, int goal) async =>
      Either.right(unit);

  @override
  Future<Either<Failure, Unit>> saveDay(DayLog log) async => Either.right(unit);

  @override
  Future<Either<Failure, DayLog>> day(DateTime date, int goal) async =>
      Either.right(DayLog(date: date, goal: goal, sessions: const []));

  @override
  Future<Either<Failure, List<DayLog>>> range(
    DateTime from,
    DateTime to,
    int goal,
  ) async {
    final days = <DayLog>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    while (!cursor.isAfter(last)) {
      days.add(DayLog(
        date: cursor,
        goal: goal,
        sessions: [
          PomoSession(
            id: '${cursor.day}-1',
            start: DateTime(cursor.year, cursor.month, cursor.day, 10),
            minutes: 25,
            category: 'разработка',
            task: 'Задача',
          ),
        ],
      ));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return Either.right(days);
  }
}

void main() {
  /// Вспомогательный метод монтирования экрана с заданным начальным курсом и размером окна.
  Future<void> pumpCourseScreen(
    WidgetTester tester, {
    required Course course,
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settingsCubit = SettingsCubit(
      _MemSettingsRepo(),
      initial: AppSettings.fromJson(const {}, fallbackPath: '.'),
      onStoragePathChanged: (_) {},
    );
    await settingsCubit.load();
    addTearDown(settingsCubit.close);

    final courseRepo = _MemCourseRepo(course);
    final journalRepo = _MemJournal();
    final directionsCubit = DirectionsCubit(courseRepo, journalRepo);
    await directionsCubit.refresh();
    addTearDown(directionsCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settingsCubit),
            BlocProvider.value(value: directionsCubit),
          ],
          child: const Scaffold(body: CourseScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'экран рендерится с пустым списком направлений и показывает пустое состояние',
    (tester) async {
      await pumpCourseScreen(
        tester,
        course: (directions: const [], milestones: const []),
        size: const Size(1280, 900),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CourseScreen), findsOneWidget);
      // Проверяем наличие текста пустого состояния из S.courseEmptyDirections
      expect(find.text(S.courseEmptyDirections), findsOneWidget);
      // Проверяем кнопку «Добавить направление»
      expect(find.text(S.courseAddDirection), findsWidgets);
    },
  );

  testWidgets(
    'с одним направлением и тремя вехами, из которых одна закрыта, на экране видно «веха 1 из 3»',
    (tester) async {
      final now = DateTime.now();
      final course = (
        directions: const [
          Direction(
            id: 'd1',
            name: 'Флагманский продукт',
            order: 0,
            categories: ['разработка'],
          ),
        ],
        milestones: [
          Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Анализ требований',
            order: 0,
            doneSprint: '2026-W30',
            doneAt: now,
          ),
          const Milestone(
            id: 'm2',
            directionId: 'd1',
            title: 'Прототип MVP',
            order: 1,
          ),
          const Milestone(
            id: 'm3',
            directionId: 'd1',
            title: 'Релиз в продакшен',
            order: 2,
          ),
        ],
      );

      await pumpCourseScreen(
        tester,
        course: course,
        size: const Size(1280, 900),
      );

      expect(tester.takeException(), isNull);
      // Проверяем заголовок направления
      expect(find.text('Флагманский продукт'), findsWidgets);
      // Проверяем строку прогресса «веха 1 из 3»
      expect(find.text(S.ladderProgress(1, 3)), findsOneWidget);
      // Проверяем следующую незакрытую веху в строке карточки
      expect(find.textContaining('Прототип MVP'), findsOneWidget);
    },
  );

  testWidgets(
    'тап по карточке раскрывает лестницу и показывает названия вех',
    (tester) async {
      final now = DateTime.now();
      final course = (
        directions: const [
          Direction(
            id: 'd1',
            name: 'Машинное обучение',
            order: 0,
          ),
        ],
        milestones: [
          Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Сбор датасета',
            order: 0,
            doneSprint: '2026-W29',
            doneAt: now,
          ),
          const Milestone(
            id: 'm2',
            directionId: 'd1',
            title: 'Обучение нейросети',
            order: 1,
          ),
          const Milestone(
            id: 'm3',
            directionId: 'd1',
            title: 'Интеграция в пайплайн',
            order: 2,
          ),
        ],
      );

      await pumpCourseScreen(
        tester,
        course: course,
        size: const Size(1280, 900),
      );

      // До тапа названия вех закрыты (не отображаются внутри лестницы)
      expect(find.text('Сбор датасета'), findsNothing);
      expect(find.text('Интеграция в пайплайн'), findsNothing);

      // Тапаем по карточке направления
      await tester.tap(find.text('Машинное обучение').first);
      await tester.pumpAndSettle();

      // После тапа лестница раскрылась — видны все три вехи
      expect(find.text('Сбор датасета'), findsOneWidget);
      expect(find.text('Обучение нейросети'), findsWidgets);
      expect(find.text('Интеграция в пайплайн'), findsOneWidget);

      // Повторный тап сворачивает лестницу обратно
      await tester.tap(find.text('Машинное обучение').first);
      await tester.pumpAndSettle();

      expect(find.text('Сбор датасета'), findsNothing);
      expect(find.text('Интеграция в пайплайн'), findsNothing);
    },
  );

  testWidgets(
    'экран не переполняется на узком экране (380px) и на широком (1400px)',
    (tester) async {
      final course = (
        directions: const [
          Direction(
            id: 'd1',
            name: 'Очень длинное название стратегического направления для проверки переполнения',
            order: 0,
            categories: ['разработка', 'бизнес'],
          ),
        ],
        milestones: [
          const Milestone(
            id: 'm1',
            directionId: 'd1',
            title: 'Первая подробная веха с развернутым описанием',
            order: 0,
          ),
        ],
      );

      // Проверка на узком экране телефона (380px)
      await pumpCourseScreen(
        tester,
        course: course,
        size: const Size(380, 800),
      );
      expect(tester.takeException(), isNull);

      // Проверка на широком экране (1400px)
      await pumpCourseScreen(
        tester,
        course: course,
        size: const Size(1400, 900),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
