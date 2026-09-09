import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/app/strings.dart';
import 'package:pomodoro_tracker/domain/entities/app_settings.dart';

void main() {
  tearDown(() => S.lang = AppLanguage.ru);

  test('S переключается между ru и en по S.lang', () {
    expect(S.start, 'Старт');
    S.lang = AppLanguage.en;
    expect(S.start, 'Start');
  });

  test('formatMinutesUi использует локализованные единицы времени', () {
    S.lang = AppLanguage.ru;
    expect(formatMinutesUi(90), '1ч 30м');
    S.lang = AppLanguage.en;
    expect(formatMinutesUi(90), '1h 30m');
  });

  test('строки Курса переключаются между ru и en по S.lang', () {
    S.lang = AppLanguage.ru;
    expect(S.navCourse, 'Курс');
    expect(S.courseDirections, 'Направления');
    expect(S.courseLadder, 'Лестница вех');
    expect(S.tooManyDirections(5), 'Активных направлений: 5. Работает 2–4 — остальное лучше на паузу.');
    expect(S.ladderProgress(2, 5), 'веха 2 из 5');
    expect(S.paceLabel('1.5'), 'темп 1.5 вех/мес');
    expect(S.etaLabel('2026-10-15'), 'при текущем темпе — к 2026-10-15');
    expect(S.deleteDirectionConfirm('Фокус'), 'Удалить направление Фокус вместе с его вехами?');

    S.lang = AppLanguage.en;
    expect(S.navCourse, 'Course');
    expect(S.courseDirections, 'Directions');
    expect(S.courseLadder, 'Milestone ladder');
    expect(S.tooManyDirections(5), 'Active directions: 5. 2–4 works best — pause the rest.');
    expect(S.ladderProgress(2, 5), 'milestone 2 of 5');
    expect(S.paceLabel('1.5'), 'pace 1.5 milestones/mo');
    expect(S.etaLabel('2026-10-15'), 'at current pace — by 2026-10-15');
    expect(S.deleteDirectionConfirm('Focus'), 'Delete direction Focus along with its milestones?');
  });
}

