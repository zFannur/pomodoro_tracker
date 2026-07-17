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
}
