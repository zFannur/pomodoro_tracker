import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/entities/app_settings.dart';

/// Синтезирует WAV-звуки при первом запуске и проигрывает их.
/// ponytail: генерация тонов вместо бандла аудио-ассетов — ноль бинарников в репо.
class SoundService {
  // Ленивая инициализация: в юнит-тестах платформенные каналы недоступны.
  AudioPlayer? _finishPlayer;
  AudioPlayer? _tickPlayer;
  final Map<String, String> _paths = {};

  static const _rate = 44100;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final sounds = <String, List<double>>{
      FinishSound.bell.name: _bell(),
      FinishSound.beep.name: _beep(),
      FinishSound.chime.name: _chime(),
      FinishSound.cuckoo.name: _cuckoo(),
      FinishSound.guitar.name: _guitar(),
      FinishSound.maramba.name: _maramba(),
      FinishSound.organ.name: _organ(),
      FinishSound.rise.name: _rise(),
      FinishSound.satellite.name: _satellite(),
      FinishSound.school.name: _school(),
      'tick': _tick(),
    };
    for (final entry in sounds.entries) {
      final file = File(
        '${dir.path}${Platform.pathSeparator}sound_${entry.key}.wav',
      );
      if (!await file.exists()) {
        await file.writeAsBytes(_wav(entry.value), flush: true);
      }
      _paths[entry.key] = file.path;
    }
  }

  Future<void> playFinish(FinishSound sound, double volume) async {
    final path = _paths[sound.name];
    if (path == null) return;
    final player = _finishPlayer ??= AudioPlayer();
    await player.stop();
    await player.setVolume(volume.clamp(0, 1));
    await player.play(DeviceFileSource(path));
  }

  Future<void> playTick(double volume) async {
    final path = _paths['tick'];
    if (path == null) return;
    final player = _tickPlayer ??= AudioPlayer();
    await player.stop();
    await player.setVolume((volume * 0.5).clamp(0, 1));
    await player.play(DeviceFileSource(path));
  }

  Future<void> dispose() async {
    await _finishPlayer?.dispose();
    await _tickPlayer?.dispose();
  }

  // -- синтез ---------------------------------------------------------------

  static List<double> _bell() {
    return _tone(
      seconds: 1.4,
      sample: (t) =>
          (math.sin(2 * math.pi * 880 * t) +
              0.5 * math.sin(2 * math.pi * 1760 * t)) *
          math.exp(-3.5 * t) *
          0.6,
    );
  }

  static List<double> _beep() {
    return _tone(
      seconds: 0.5,
      sample: (t) {
        final square = math.sin(2 * math.pi * 1000 * t) >= 0 ? 1.0 : -1.0;
        final fade = math.min(1.0, (0.5 - t) * 20).clamp(0.0, 1.0);
        return square * 0.25 * fade;
      },
    );
  }

  static List<double> _chime() {
    return _tone(
      seconds: 1.6,
      sample: (t) {
        final first = math.sin(2 * math.pi * 660 * t) * math.exp(-4 * t);
        final second = t > 0.4
            ? math.sin(2 * math.pi * 990 * (t - 0.4)) * math.exp(-4 * (t - 0.4))
            : 0.0;
        return (first + second) * 0.5;
      },
    );
  }

  static List<double> _tick() {
    return _tone(
      seconds: 0.04,
      sample: (t) =>
          math.sin(2 * math.pi * 2200 * t) * math.exp(-120 * t) * 0.8,
    );
  }

  static List<double> _cuckoo() {
    // Две ноты «ку-ку»: F#5 → D5 с мягкой огибающей.
    double note(double t, double freq, double start, double len) {
      if (t < start || t > start + len) return 0;
      final x = t - start;
      final env = math.sin(math.pi * x / len);
      return math.sin(2 * math.pi * freq * x) * env * 0.5;
    }

    return _tone(
      seconds: 0.65,
      sample: (t) => note(t, 740, 0, 0.22) + note(t, 587, 0.32, 0.28),
    );
  }

  static List<double> _guitar() {
    // Струна (Карплус–Стронг): шумовой импульс через линию задержки.
    const seconds = 1.3;
    const freq = 330.0;
    final period = (_rate / freq).round();
    final rnd = math.Random(7);
    final delay = List<double>.generate(
      period,
      (_) => rnd.nextDouble() * 2 - 1,
    );
    final out = List<double>.filled((seconds * _rate).round(), 0);
    var idx = 0;
    for (var i = 0; i < out.length; i++) {
      final next = delay[(idx + 1) % period];
      final smoothed = 0.996 * 0.5 * (delay[idx] + next);
      out[i] = delay[idx] * 0.6;
      delay[idx] = smoothed;
      idx = (idx + 1) % period;
    }
    return out;
  }

  static List<double> _maramba() {
    // Деревянный удар: основной тон + быстро гаснущая высокая гармоника.
    return _tone(
      seconds: 0.9,
      sample: (t) =>
          (math.sin(2 * math.pi * 440 * t) * math.exp(-6 * t) +
              0.6 * math.sin(2 * math.pi * 1760 * t) * math.exp(-30 * t)) *
          0.55,
    );
  }

  static List<double> _organ() {
    // Аккорд с медленной атакой и лёгким вибрато.
    return _tone(
      seconds: 1.4,
      sample: (t) {
        final attack = math.min(1.0, t * 6);
        final release = math.min(1.0, (1.4 - t) * 4).clamp(0.0, 1.0);
        final vibrato = 1 + 0.004 * math.sin(2 * math.pi * 5 * t);
        final chord =
            math.sin(2 * math.pi * 262 * vibrato * t) +
            0.7 * math.sin(2 * math.pi * 330 * vibrato * t) +
            0.6 * math.sin(2 * math.pi * 392 * vibrato * t);
        return chord * attack * release * 0.22;
      },
    );
  }

  static List<double> _rise() {
    // Плавный подъём 400 → 1200 Гц.
    return _tone(
      seconds: 0.9,
      sample: (t) {
        final k = t / 0.9;
        final freq = 400 + 800 * k * k;
        final env = math.sin(math.pi * k);
        return math.sin(2 * math.pi * freq * t) * env * 0.5;
      },
    );
  }

  static List<double> _satellite() {
    // Три коротких радио-бипа с металлическим призвуком.
    double blip(double t, double start) {
      if (t < start || t > start + 0.12) return 0;
      final x = t - start;
      final env = math.exp(-25 * x);
      return (math.sin(2 * math.pi * 1200 * x) +
              0.4 * math.sin(2 * math.pi * 2400 * x)) *
          env *
          0.5;
    }

    return _tone(
      seconds: 0.8,
      sample: (t) => blip(t, 0) + blip(t, 0.25) + blip(t, 0.5),
    );
  }

  static List<double> _school() {
    // Школьный звонок: тон с тремоло «молоточка».
    return _tone(
      seconds: 1.6,
      sample: (t) {
        final tremolo = 0.55 + 0.45 * math.sin(2 * math.pi * 16 * t).abs();
        final fade = math.min(1.0, (1.6 - t) * 3).clamp(0.0, 1.0);
        return (math.sin(2 * math.pi * 1480 * t) +
                0.3 * math.sin(2 * math.pi * 2220 * t)) *
            tremolo *
            fade *
            0.35;
      },
    );
  }

  static List<double> _tone({
    required double seconds,
    required double Function(double t) sample,
  }) {
    final count = (seconds * _rate).round();
    return List<double>.generate(count, (i) => sample(i / _rate));
  }

  static Uint8List _wav(List<double> samples) {
    final data = ByteData(44 + samples.length * 2);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(
        44 + i * 2,
        (samples[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return data.buffer.asUint8List();
  }
}
