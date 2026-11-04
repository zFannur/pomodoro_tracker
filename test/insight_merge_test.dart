import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_tracker/data/data_merge.dart';

void main() {
  Map<String, dynamic> merge(
    Map<String, dynamic> winner,
    Map<String, dynamic> loser,
    bool localWins,
  ) =>
      jsonDecode(
            mergeData(
              jsonEncode(localWins ? winner : loser),
              jsonEncode(localWins ? loser : winner),
              localWins: localWins,
            ),
          )
          as Map<String, dynamic>;
  Map<String, dynamic> dayDoc(Map<String, dynamic> day) => {
    'days': {'2026-11-04': day},
  };

  for (final localWins in [true, false]) {
    group('localWins=$localWins', () {
      test('эпизоды объединяются по id и сортируются с учётом ночи', () {
        final merged = merge(
          dayDoc({
            'goal': 8,
            'e': [
              {'id': 'night', 't': '00:30'},
              {'id': 'same', 't': '15:00', 'cause': 'big'},
            ],
          }),
          dayDoc({
            'e': [
              {'id': 'morning', 't': '05:00'},
              {'id': 'same', 't': '16:00', 'cause': 'tired'},
              {'id': 'evening', 't': '23:59'},
            ],
          }),
          localWins,
        );
        final episodes = merged['days']['2026-11-04']['e'] as List;
        expect(episodes.map((e) => e['id']), [
          'morning',
          'same',
          'evening',
          'night',
        ]);
        expect(episodes[1]['cause'], 'big');
        final once = jsonEncode(merged);
        expect(mergeData(once, once, localWins: localWins), once);
      });

      test('ck сливается по полям, конфликт решает победитель', () {
        final merged = merge(
          dayDoc({
            'ck': {'sl': 4, 'en': 3},
          }),
          dayDoc({
            'ck': {'md': 5, 'en': 2},
          }),
          localWins,
        );
        expect(merged['days']['2026-11-04']['ck'], {'sl': 4, 'en': 3, 'md': 5});
      });

      test('IPS: непустой список победителя, иначе список проигравшего', () {
        for (final win in [
          <int>[],
          [1, 2, 3],
        ]) {
          final merged = merge(
            dayDoc({'ips': win}),
            dayDoc({
              'ips': [4, 5, 4],
            }),
            localWins,
          );
          expect(
            merged['days']['2026-11-04']['ips'],
            win.isEmpty ? [4, 5, 4] : win,
          );
        }
        final merged = merge(
          dayDoc({'goal': 8}),
          dayDoc({
            'ips': [3, 3, 3],
          }),
          localWins,
        );
        expect(merged['days']['2026-11-04']['ips'], [3, 3, 3]);
      });

      test('пустые новые ключи опускаются', () {
        final merged = merge(
          dayDoc({'goal': 8, 'e': [], 'ck': {}, 'ips': []}),
          dayDoc({'goal': 9}),
          localWins,
        );
        final day = merged['days']['2026-11-04'] as Map;
        for (final key in ['e', 'ck', 'ips']) {
          expect(day, isNot(contains(key)));
        }
      });

      test(
        'exp/ai: победитель при конфликте, проигравший при отсутствии ключа',
        () {
          final exp = {'h': 'гипотеза', 'st': 'firstStep', 'm': 'firstStart'};
          final ai = {'at': '2026-11-04T10:00', 'summary': 'итог'};
          Map<String, dynamic> sprintDoc(Map<String, dynamic> sprint) => {
            'sprints': {'2026-W45': sprint},
          };
          final fallback = merge(
            sprintDoc({'goal': 40}),
            sprintDoc({'exp': exp, 'ai': ai}),
            localWins,
          );
          expect(fallback['sprints']['2026-W45']['exp'], exp);
          expect(fallback['sprints']['2026-W45']['ai'], ai);
          final conflict = merge(
            sprintDoc({'exp': exp, 'ai': ai}),
            sprintDoc({
              'exp': {'h': 'другое'},
              'ai': {'summary': 'другое'},
            }),
            localWins,
          );
          expect(conflict['sprints']['2026-W45']['exp'], exp);
          expect(conflict['sprints']['2026-W45']['ai'], ai);
        },
      );

      test('надгробия чистят эпизоды даже в дне только проигравшего', () {
        final merged = merge(
          {
            'graves': {'dead': '2026-11-04T10:00Z'},
          },
          dayDoc({
            'e': [
              {'id': 'dead', 't': '09:00'},
              {'id': 'alive', 't': '10:00'},
            ],
          }),
          localWins,
        );
        final episodes = merged['days']['2026-11-04']['e'] as List;
        expect(episodes.map((e) => e['id']), ['alive']);
      });
    });
  }
}
