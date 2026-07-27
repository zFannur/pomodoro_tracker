import 'dart:convert';

import '../domain/entities/pomo_session.dart' show dayStartHour;

/// Слияние двух снимков data.json — задачи, журнал, спринты и надгробия.
///
/// Чистая функция без IO: её проще всего проверить тестами, а вся неприятная
/// часть синхронизации именно здесь.
///
/// [localWins] решает только спорные СКАЛЯРЫ (цель дня, веха спринта) и
/// содержимое записей с одинаковым id. Списки не выбирают победителя —
/// они объединяются, потому что журнал по природе дописывается: помидор,
/// записанный офлайн на телефоне, обязан пережить любую правку на другом
/// устройстве.
String mergeData(String? local, String remote, {required bool localWins}) {
  if (local == null || local.trim().isEmpty) return remote;

  Map<String, dynamic> parse(String s) {
    final json = jsonDecode(s);
    return json is Map<String, dynamic> ? json : <String, dynamic>{};
  }

  Map<String, dynamic> localJson;
  Map<String, dynamic> remoteJson;
  try {
    localJson = parse(local);
    remoteJson = parse(remote);
  } on FormatException {
    // Локальный файл битый — удалённый хотя бы читается.
    return remote;
  }

  final winner = localWins ? localJson : remoteJson;
  final loser = localWins ? remoteJson : localJson;

  // База — карта победителя ЦЕЛИКОМ, а не собранная заново из известных
  // ключей: иначе любая секция, о которой эта функция не знает, молча
  // исчезала бы при первом же слиянии и после каждого переподключения.
  final result = <String, dynamic>{...winner};

  result['todo'] = _mergeById(winner['todo'], loser['todo']);
  result['planner'] = _mergeById(winner['planner'], loser['planner']);
  result['days'] = _mergeDays(winner['days'], loser['days']);
  result['sprints'] = _mergeSprints(winner['sprints'], loser['sprints']);
  result['rollover'] = _mergeRollover(winner['rollover'], loser['rollover']);

  // Таймер — не список: у него ровно одно актуальное состояние, побеждает
  // более свежий снимок независимо от localWins.
  final timer = _laterTimer(winner['timer'], loser['timer']);
  if (timer == null) {
    result.remove('timer');
  } else {
    result['timer'] = timer;
  }

  final graves = _mergeGraves(winner['graves'], loser['graves']);
  result['graves'] = graves;

  // Удаление побеждает всегда и не зависит от localWins: как только судьбу
  // записи начинают решать часы устройств, возвращается расхождение времени
  // между Android и Windows. Время в graves нужно только для чистки.
  if (graves.isNotEmpty) _purge(result, graves.keys.toSet());

  return jsonEncode(result);
}

List<Map<String, dynamic>> _list(Object? raw) => [
  if (raw is List) ...raw.whereType<Map<String, dynamic>>(),
];

Map<String, dynamic> _map(Object? raw) =>
    raw is Map<String, dynamic> ? raw : const {};

/// Объединение списков записей: порядок победителя, незнакомое дописывается
/// в конец. При совпадении id остаётся версия победителя.
List<Map<String, dynamic>> _mergeById(Object? win, Object? lose) {
  final winList = _list(win);
  final seen = <String>{
    for (final e in winList)
      if (e['id'] is String) e['id'] as String,
  };
  return [
    ...winList,
    for (final e in _list(lose))
      // Запись без id мержить не по чему — считаем незнакомой и сохраняем.
      if (e['id'] is! String || seen.add(e['id'] as String)) e,
  ];
}

/// Объединение по значению, порядок победителя первым. Заметки дня и строки
/// «сделано за неделю» идентификаторов не имеют: они пишутся со штампом
/// времени в тексте, а удаления у них в интерфейсе нет.
List<String> _mergeValues(Object? win, Object? lose) {
  final result = <String>[if (win is List) ...win.whereType<String>()];
  for (final v in lose is List ? lose.whereType<String>() : const <String>[]) {
    if (!result.contains(v)) result.add(v);
  }
  return result;
}

/// Минута внутри логического дня для строки времени `HH:mm`.
/// Часы 0–4 принадлежат концу дня — та же граница, что в [dayStartHour].
int _slot(Object? raw) {
  final parts = '$raw'.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return ((h < dayStartHour ? h + 24 : h) * 60) + m;
}

Map<String, dynamic> _mergeDays(Object? win, Object? lose) {
  final winDays = _map(win);
  final loseDays = _map(lose);
  final result = <String, dynamic>{};
  for (final key in {...winDays.keys, ...loseDays.keys}) {
    final w = _map(winDays[key]);
    final l = _map(loseDays[key]);
    if (w.isEmpty) {
      result[key] = l;
      continue;
    }
    if (l.isEmpty) {
      result[key] = w;
      continue;
    }
    final sessions = _mergeById(w['s'], l['s'])
      // Порядок восстанавливается сортировкой по времени — одинаково на
      // обоих устройствах, поэтому хранить его не нужно. Сортируем по
      // ЛОГИЧЕСКОМУ времени: день длится 05:00→05:00, и запись в 00:30 стоит
      // в конце дня, а не в начале, как решила бы сортировка строк.
      ..sort((a, b) => _slot(a['t']).compareTo(_slot(b['t'])));
    result[key] = {...w, 's': sessions, 'n': _mergeValues(w['n'], l['n'])};
  }
  return result;
}

Map<String, dynamic> _mergeSprints(Object? win, Object? lose) {
  final winSprints = _map(win);
  final loseSprints = _map(lose);
  final result = <String, dynamic>{};
  for (final key in {...winSprints.keys, ...loseSprints.keys}) {
    final w = _map(winSprints[key]);
    final l = _map(loseSprints[key]);
    if (w.isEmpty) {
      result[key] = l;
      continue;
    }
    if (l.isEmpty) {
      result[key] = w;
      continue;
    }
    // goal и milestone — скаляры победителя, done объединяется. Базой идёт
    // {...l, ...w}, а не {...w}: encode опускает пустую веху, поэтому у
    // победителя ключа могло просто не быть — и непустая веха проигравшего
    // не «проигрывала скаляр», а молча исчезала у обоих устройств.
    result[key] = {...l, ...w, 'done': _mergeValues(w['done'], l['done'])};
  }
  return result;
}

/// Снимок таймера: тот, у кого `savedAt` больше.
Map<String, dynamic>? _laterTimer(Object? a, Object? b) {
  final x = a is Map<String, dynamic> ? a : null;
  final y = b is Map<String, dynamic> ? b : null;
  if (x == null) return y;
  if (y == null) return x;
  final xs = (x['savedAt'] as num?)?.toInt() ?? 0;
  final ys = (y['savedAt'] as num?)?.toInt() ?? 0;
  return ys > xs ? y : x;
}

/// Надгробия: объединение по id, время — более позднее.
Map<String, dynamic> _mergeGraves(Object? win, Object? lose) {
  final result = <String, dynamic>{};
  for (final source in [_map(lose), _map(win)]) {
    for (final e in source.entries) {
      if (e.value is! String) continue;
      final existing = result[e.key];
      if (existing is! String || (e.value as String).compareTo(existing) > 0) {
        result[e.key] = e.value;
      }
    }
  }
  return result;
}

/// Отметки о смене дня/недели — максимум строк, а не по времени: dateKey и
/// sprintId сортируются лексикографически, поэтому дрейф часов ни при чём,
/// а повторного сброса лягушек не будет.
Map<String, dynamic> _mergeRollover(Object? win, Object? lose) {
  final w = _map(win);
  final l = _map(lose);
  if (w.isEmpty && l.isEmpty) return const {};
  String? later(String key) {
    final a = w[key] is String ? w[key] as String : null;
    final b = l[key] is String ? l[key] as String : null;
    if (a == null) return b;
    if (b == null) return a;
    return a.compareTo(b) >= 0 ? a : b;
  }

  return {
    ...w,
    if (later('day') != null) 'day': later('day'),
    if (later('week') != null) 'week': later('week'),
  };
}

/// Вычесть похороненные id из всех списков записей.
void _purge(Map<String, dynamic> doc, Set<String> graves) {
  List<Map<String, dynamic>> alive(Object? raw) => [
    for (final e in _list(raw))
      if (e['id'] is! String || !graves.contains(e['id'])) e,
  ];

  doc['todo'] = alive(doc['todo']);
  doc['planner'] = alive(doc['planner']);
  final days = _map(doc['days']);
  doc['days'] = {
    for (final e in days.entries)
      e.key: {..._map(e.value), 's': alive(_map(e.value)['s'])},
  };
}
