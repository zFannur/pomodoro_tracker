import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../data/activity_store.dart';
import '../data/markdown_codec.dart' show dateKey;
import '../domain/entities/pomo_session.dart' show logicalDate;

/// Период опроса активного окна, сек. Каждый тик прибавляет столько же.
const activityTickSeconds = 5;

/// Без ввода дольше этого — человек отошёл, тик не считается.
const _idleLimitSeconds = 120;

/// Сколько дней хранить.
const _keepDays = 60;

/// Раз в сколько сбрасывать данные на диск.
const _flushEvery = Duration(seconds: 60);

/// Браузеры: exe → короткое имя для списка.
const browserNames = {
  'chrome.exe': 'Chrome',
  'msedge.exe': 'Edge',
  'firefox.exe': 'Firefox',
  'brave.exe': 'Brave',
  'opera.exe': 'Opera',
};

/// Названия браузеров в заголовках окон («Microsoft Edge» бывает с невидимым
/// пробелом внутри).
const _brands =
    r'(?:Google Chrome|Microsoft[\u200B\s]*Edge|Mozilla Firefox|Brave|Opera)';

/// Хвост заголовка окна браузера: « - Google Chrome», « — Mozilla Firefox»,
/// плюс имя профиля после него (« - Google Chrome - Работа»).
final _browserTail = RegExp(
  r'\s+[-—–]\s+' + _brands + r'(?:\s+[-—–]\s+[^-—–]*)?$',
  caseSensitive: false,
);

/// Заголовок — одно имя браузера (пустая вкладка): названия нет.
final _bareBrand = RegExp('^$_brands\$', caseSensitive: false);

/// Название вкладки из заголовка окна браузера. Для не-браузеров — пустая
/// строка: заголовок остальных окон не храним (меньше данных и шума).
String browserTabTitle(String exe, String windowTitle) {
  if (!browserNames.containsKey(exe.toLowerCase())) return '';
  final tab = windowTitle.replaceFirst(_browserTail, '').trim();
  if (_bareBrand.hasMatch(tab)) return '';
  return tab.length > 120 ? tab.substring(0, 120) : tab;
}

/// Прибавляет тик к агрегату дня. [title] — уже очищенное название вкладки
/// (см. [browserTabTitle]); [inFocus] — идёт помидор.
void addTick(
  Map<String, ActivityEntry> day, {
  required String app,
  String title = '',
  required int seconds,
  required bool inFocus,
}) {
  final entry = day.putIfAbsent(
    '$app|$title',
    () => ActivityEntry(app: app, title: title),
  );
  entry.seconds += seconds;
  if (inFocus) entry.focusSeconds += seconds;
}

/// Удаляет дни старше [keep] суток (включая [today]). Ключи — «yyyy-MM-dd»,
/// поэтому сравнение строк совпадает со сравнением дат.
void pruneDays<T>(
  Map<String, T> days,
  DateTime today, {
  int keep = _keepDays,
}) {
  final cutoff = dateKey(DateTime(today.year, today.month, today.day - keep + 1));
  days.removeWhere((key, _) => key.compareTo(cutoff) < 0);
}

/// Учёт активного окна Windows. На остальных платформах — no-op.
class ActivityTracker {
  ActivityTracker({required this.store, required this.inPomodoro});

  final ActivityStore store;

  /// Идёт ли сейчас помидор: геттер, а не сам TimerCubit.
  final bool Function() inPomodoro;

  ActivityData data = ActivityData();
  final _ticks = StreamController<void>.broadcast();
  Timer? _timer;
  bool _dirty = false;
  DateTime _lastFlush = clock.now();

  /// Сигнал «данные изменились» — на него обновляется экран.
  Stream<void> get ticks => _ticks.stream;

  Future<void> start() async {
    if (!Platform.isWindows) return;
    data = await store.load();
    pruneDays(data.days, logicalDate(clock.now()));
    _lastFlush = clock.now();
    _timer = Timer.periodic(
      const Duration(seconds: activityTickSeconds),
      (_) => _tick(),
    );
    _ticks.add(null);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await flush();
    await _ticks.close();
  }

  Future<void> toggleDistracting(String key) async {
    if (!data.distracting.remove(key)) data.distracting.add(key);
    _dirty = true;
    await flush();
  }

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    _lastFlush = clock.now();
    pruneDays(data.days, logicalDate(_lastFlush));
    await store.save(data);
  }

  void _tick() {
    final now = clock.now();
    _record(now);
    if (_dirty && now.difference(_lastFlush) >= _flushEvery) {
      unawaited(flush());
    }
  }

  void _record(DateTime now) {
    if (_idleSeconds() > _idleLimitSeconds) return;
    final window = _foreground();
    if (window == null) return;
    addTick(
      data.days.putIfAbsent(dateKey(logicalDate(now)), () => {}),
      app: window.exe,
      title: browserTabTitle(window.exe, window.title),
      seconds: activityTickSeconds,
      inFocus: inPomodoro(),
    );
    _dirty = true;
    _ticks.add(null);
  }

  /// Секунд с последнего ввода (мышь/клавиатура).
  int _idleSeconds() {
    final info = calloc<LASTINPUTINFO>();
    try {
      info.ref.cbSize = sizeOf<LASTINPUTINFO>();
      if (GetLastInputInfo(info) == 0) return 0;
      // Оба значения — 32-битные миллисекунды с запуска, маска держит переход.
      return ((GetTickCount() - info.ref.dwTime) & 0xFFFFFFFF) ~/ 1000;
    } finally {
      calloc.free(info);
    }
  }

  /// exe и заголовок окна на переднем плане; null — окна нет или процесс
  /// недоступен (например, запущен от администратора).
  ({String exe, String title})? _foreground() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return null;
    final exe = _exeName(hwnd);
    if (exe == null) return null;
    // Заголовок читаем только у браузеров — у остальных он не нужен.
    final title = browserNames.containsKey(exe) ? _windowTitle(hwnd) : '';
    return (exe: exe, title: title);
  }

  String? _exeName(int hwnd) {
    final pid = calloc<Uint32>();
    final buffer = calloc<Uint16>(1024).cast<Utf16>();
    final size = calloc<Uint32>();
    var process = 0;
    try {
      GetWindowThreadProcessId(hwnd, pid);
      if (pid.value == 0) return null;
      process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid.value);
      if (process == 0) return null;
      size.value = 1024;
      if (QueryFullProcessImageName(process, 0, buffer, size) == 0) return null;
      final path = buffer.toDartString(length: size.value);
      return path.substring(path.lastIndexOf('\\') + 1).toLowerCase();
    } finally {
      if (process != 0) CloseHandle(process);
      calloc.free(pid);
      calloc.free(buffer);
      calloc.free(size);
    }
  }

  String _windowTitle(int hwnd) {
    final length = GetWindowTextLength(hwnd);
    if (length <= 0) return '';
    final buffer = calloc<Uint16>(length + 1).cast<Utf16>();
    try {
      GetWindowText(hwnd, buffer, length + 1);
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }
}
