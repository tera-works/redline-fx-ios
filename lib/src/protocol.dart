// BLE protocol of the REDLINE FX pedal (firmware src/ble_fx.c, preset v8).
// Pure Dart: no Flutter / plugin imports, so it is unit-testable.
import 'dart:typed_data';

const String serviceUuid = '7ea00001-b5a3-f393-e0a9-e50e24dcca9e';

/// Characteristic 0xNN of the FX service.
String charUuid(int n) =>
    '7ea000${n.toRadixString(16).padLeft(2, '0')}-b5a3-f393-e0a9-e50e24dcca9e';

/// Characteristic numbers.
abstract final class Ch {
  static const int param = 0x02; // [id][u16 LE norm*65535], write without response
  static const int command = 0x03; // [cmd][arg]
  static const int footswitch = 0x07; // [ver=2, bank, released, pressed, sounding, physical]
  static const int status = 0x08; // 33 bytes: load, meters, level session
  static const int offSlot = 0x09; // [ref] + preset
  static const int onSlot = 0x0A;
  static const int live = 0x0B; // tuner / looper / mode
  static const List<int> needed = [2, 3, 7, 8, 9, 10, 11];
}

/// Command ids written to [Ch.command].
abstract final class Cmd {
  static const int tapTempo = 16;
  static const int commit = 17; // store the two staged slots
  static const int abort = 18;
  static const int tuner = 19;
  static const int looperMode = 20;
  static const int loopLevel = 21; // 0..200 %
  static const int looperAction = 22; // 1 tap, 2 stop, 3 clear
  static const int bassMode = 23;
  static const int inputTrim = 24; // arg = dB + 24, current instrument mode
}

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => message;
}

ByteData _view(Uint8List b) => ByteData.sublistView(b);

/// Footswitch characteristic (0x07).
class SwitchState {
  const SwitchState({required this.pressed, required this.physical});

  /// Which tone is sounding: false = OFF side, true = ON side.
  final bool pressed;

  /// Switch position (differs from [pressed] in looper mode).
  final bool physical;

  static SwitchState parse(Uint8List f) {
    if (f.length < 5 || f[0] != 2) throw ProtocolException('状態データが不正です');
    final pressed = f[4] != 0;
    return SwitchState(pressed: pressed, physical: f.length >= 6 ? f[5] != 0 : pressed);
  }
}

/// Status characteristic (0x08), first bytes.
class DeviceStatus {
  const DeviceStatus({required this.dspLoad, required this.oversampling, required this.saveBusy, required this.saveError});
  final double dspLoad; // percent
  final int oversampling;
  final bool saveBusy;
  final bool saveError;

  static DeviceStatus parse(Uint8List s) {
    if (s.length < 4 || s[0] != 1) throw ProtocolException('状態データが不正です');
    return DeviceStatus(
      dspLoad: (s[1] | s[2] << 8) / 10.0,
      oversampling: s[3],
      saveBusy: s.length >= 5 && s[4] != 0,
      saveError: s.length >= 6 && s[5] != 0,
    );
  }
}

/// One playing session as measured by the pedal (input above -50 dBFS until 3 s of silence).
class LevelSession {
  const LevelSession({
    required this.id,
    required this.inMax,
    required this.inAvg,
    required this.outMax,
    required this.inClips,
    required this.outClips,
    required this.durationMs,
    required this.sinceMs,
    required this.active,
  });
  final int id;
  final double inMax, inAvg, outMax; // linear 0..1
  final int inClips, outClips;
  final int durationMs, sinceMs;
  final bool active;
}

/// Level meter data from the status characteristic (0x08).
class LevelStatus {
  const LevelStatus(this.inPeak, this.outPeak, this.session);
  final double inPeak, outPeak; // since the previous read, linear 0..1
  final LevelSession? session;

  static LevelStatus parse(Uint8List s) {
    if (s.length < 33 || s[0] != 1) throw ProtocolException('状態データが不正です');
    final v = _view(s);
    double u(int o) => (s[o] | s[o + 1] << 8) / 65535.0;
    final flags = s[28];
    final session = (flags & 2) != 0
        ? LevelSession(
            id: v.getUint32(29, Endian.little),
            inMax: u(10),
            inAvg: u(12),
            outMax: u(14),
            inClips: s[16] | s[17] << 8,
            outClips: s[18] | s[19] << 8,
            durationMs: v.getUint32(20, Endian.little),
            sinceMs: v.getUint32(24, Endian.little),
            active: (flags & 1) != 0,
          )
        : null;
    return LevelStatus(u(6), u(8), session);
  }
}

/// LIVE characteristic (0x0B): tuner, looper and instrument mode.
class LiveState {
  const LiveState({
    required this.tunerOn,
    required this.looperMode,
    required this.bassMode,
    required this.loopState,
    required this.levelPercent,
    required this.hz,
    required this.clarity,
    required this.length,
    required this.position,
    required this.capacitySeconds,
    this.trimGuitar,
    this.trimBass,
  });
  final bool tunerOn, looperMode, bassMode;
  final int loopState; // 0 empty, 1 rec, 2 play, 3 dub, 4 stop
  final int levelPercent;
  final double hz, clarity;
  final int length, position; // samples @ 48 kHz
  final int capacitySeconds;
  final int? trimGuitar, trimBass; // input trim dB (firmware with LIVE >= 24 bytes)

  static const List<String> stateNames = ['EMPTY', 'REC', 'PLAY', 'DUB', 'STOP'];

  static LiveState parse(Uint8List b) {
    if (b.length < 22 || b[0] != 1) throw ProtocolException('状態データが不正です');
    final v = _view(b);
    return LiveState(
      tunerOn: (b[1] & 1) != 0,
      looperMode: (b[1] & 2) != 0,
      bassMode: (b[1] & 4) != 0,
      loopState: b[2],
      levelPercent: b[3] * 2,
      hz: v.getFloat32(4, Endian.little),
      clarity: v.getFloat32(8, Endian.little),
      length: v.getUint32(12, Endian.little),
      position: v.getUint32(16, Endian.little),
      capacitySeconds: v.getUint16(20, Endian.little),
      trimGuitar: b.length >= 24 ? b[22] - 24 : null,
      trimBass: b.length >= 24 ? b[23] - 24 : null,
    );
  }

  bool get recording => loopState == 1 || loopState == 3;
  bool get playing => loopState == 2;

  String describe() {
    final s = loopState >= 0 && loopState <= 4 ? stateNames[loopState] : '?';
    String sec(int n) => (n / 48000.0).toStringAsFixed(1);
    switch (loopState) {
      case 0:
        return '$s  /  max $capacitySeconds s';
      case 1:
        return '● $s  ${sec(length)} s';
      case 4:
        return '■ $s  ${sec(length)} s';
      default:
        return '${loopState == 3 ? '●' : '▶'} $s  ${sec(position)} / ${sec(length)} s';
    }
  }
}

/// [id][u16 LE] parameter write.
Uint8List encodeParam(int id, double norm) {
  final v = (norm.clamp(0.0, 1.0) * 65535).round();
  return Uint8List.fromList([id, v & 0xff, v >> 8]);
}

Uint8List encodeCommand(int cmd, int arg) => Uint8List.fromList([cmd, arg & 0xff]);
