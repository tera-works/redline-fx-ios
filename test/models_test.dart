// Port of the .NET --self-test (codec, migration, library modes, level log, tuner math).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:redline_fx/src/level_log.dart';
import 'package:redline_fx/src/models.dart';
import 'package:redline_fx/src/protocol.dart';

void main() {
  final defaults = Defaults.parse(File('assets/defaults.json').readAsStringSync());
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('redline-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('factory data', () {
    expect(defaults.params.length, Tone.paramCount);
    for (var i = 0; i < defaults.params.length; i++) {
      expect(defaults.params[i].id, i);
    }
    expect(defaults.order.length, defaults.blocks.length);
    expect(defaults.order.toSet().length, defaults.blocks.length);
    defaults.library.validate();
    defaults.bassLibrary.validate();
    expect(defaults.bassLibrary.tones.length, 48);
    expect(defaults.bassPairs.length, 32);
  });

  test('preset codec v8', () {
    for (final t in defaults.library.tones) {
      final r = Tone.decode(t.encode());
      expect(r.name, t.name);
      expect(r.values, t.values);
    }
    final x = defaults.library.tones[1].copy();
    x.values[Tone.driveTypeId] = 1;
    x.values[70] = .8;
    x.values[89] = 1;
    x.values[102] = .25;
    x.values[106] = .4;
    final b = x.encode();
    expect(b.length, 457);
    final r = Tone.decode(b);
    expect(r.values[70], closeTo(.8, 1e-6));
    expect(r.values[106], closeTo(.4, 1e-6));
    expect(() => Tone.decode(Uint8List(Tone.encodedLengthFor(106))), throwsA(isA<LibraryException>()));
    // v7 firmware tone: same bytes, fewer Mod/Delay/Reverb types -> keep the chosen type
    final y = defaults.library.tones[1].copy();
    y.values[Tone.modTypeId] = 1; // v7 UNI-VIBE (index 4 of 5)
    y.values[Tone.delayTypeId] = 1; // v7 TAPE (index 2 of 3)
    y.values[Tone.reverbTypeId] = .5; // v7 HALL (index 1 of 3)
    final b7 = y.encode()..[0] = 7;
    final r7 = Tone.decode(b7);
    expect(defaults.params[Tone.modTypeId].display(r7.values[Tone.modTypeId]), 'UNI-VIBE');
    expect(defaults.params[Tone.delayTypeId].display(r7.values[Tone.delayTypeId]), 'TAPE');
    expect(defaults.params[Tone.reverbTypeId].display(r7.values[Tone.reverbTypeId]), 'HALL');
    expect(defaults.params[Tone.modTypeId].display(1), 'RING MOD');
    expect(defaults.params[Tone.reverbTypeId].display(1), 'SHIMMER');
    expect(defaults.params[Tone.delayTypeId].display(1), 'REVERSE');
  });

  test('settings migration v2..v6', () {
    final fresh = defaults.library.clone();
    for (final fileVersion in [2, 3, 4, 5, 6]) {
      final kept = switch (fileVersion) { 2 => Tone.legacyParamCount, 3 => Tone.v4ParamCount, 4 => Tone.v5ParamCount, 5 => Tone.v6ParamCount, _ => Tone.paramCount };
      final toneVersion = fileVersion + 1;
      final json = fresh.toJson();
      json['version'] = fileVersion;
      for (final t in json['tones'] as List) {
        final m = t as Map<String, dynamic>;
        final v = (m['values'] as List).cast<double>();
        m['values'] = [for (var k = 0; k < kept; k++) Tone.toOldFormat(k, v[k], toneVersion)];
      }
      final old = LibraryData.fromJson(json);
      expect(old.migrate(), isTrue);
      old.validate();
      for (var i = 0; i < fresh.tones.length; i++) {
        final a = fresh.tones[i].values, b = old.tones[i].values;
        for (var k = 0; k < Tone.paramCount; k++) {
          if (k < kept) {
            expect(b[k], closeTo(Tone.fromOldFormat(k, Tone.toOldFormat(k, a[k], toneVersion), toneVersion), 1e-6), reason: 'tone $i param $k');
          } else {
            var d = k < Tone.v4ParamCount
                ? Tone.v4Defaults[k - Tone.legacyParamCount]
                : k < Tone.v5ParamCount
                    ? Tone.v5Defaults[k - Tone.v4ParamCount]
                    : k < Tone.v6ParamCount
                        ? Tone.v6Defaults[k - Tone.v5ParamCount]
                        : Tone.v7Defaults[k - Tone.v6ParamCount];
            if (k == Tone.ampTypeId) d = Tone.fromOldFormat(k, d, 6);
            expect(b[k], closeTo(d, 1e-6), reason: 'defaults $k');
          }
        }
      }
    }
    expect(Tone.toOldFormat(Tone.modTypeId, 4 / 6, 6), 1); // UNI-VIBE -> PHASER
    expect(Tone.toOldFormat(Tone.modTypeId, .5, 6), .5); // TREMOLO -> CHORUS
    expect(Tone.toOldFormat(Tone.modTypeId, 1, 7), .75); // RING MOD -> TREMOLO
    expect(Tone.toOldFormat(Tone.reverbTypeId, 1, 7), .5); // SHIMMER -> HALL
    expect(Tone.toOldFormat(Tone.delayTypeId, 1, 7), 0); // REVERSE -> DIGITAL
    expect(Tone.toOldFormat(Tone.cabModelId, .75, 6), 0);
    expect(Tone.toOldFormat(Tone.ampTypeId, 1, 6), 0);
  });

  test('guitar / bass banks', () {
    final path = '${temp.path}/library.json';
    final m = Library.open(defaults, path);
    expect(m.bass, isFalse);
    m.switchMode('bass');
    expect(m.bass, isTrue);
    expect(m.data.tones[1].name, defaults.bassLibrary.tones[1].name);
    expect(m.data.syncPending, isTrue);
    m.data.tones[33].values[15] = .125;
    m.save();
    m.switchMode('guitar');
    expect(m.data.tones[1].name, defaults.library.tones[1].name);
    expect(m.data.tones[33].values[15], isNot(.125));
    final re = Library.open(defaults, path);
    expect(re.bass, isFalse);
    re.switchMode('bass');
    expect(re.data.tones[33].values[15], .125);
    re.reset();
    expect(re.bass, isTrue);
    expect(re.data.stash, isNull);
    expect(re.data.tones[33].values[15], isNot(.125));
  });

  test('rig snapshot persists', () {
    final path = '${temp.path}/library.json';
    final first = Library.open(defaults, path);
    first.data.selected = 16;
    first.storePair([first.data.tones[1].copy(), first.data.tones[2].copy()], [1, 2]);
    final second = Library.open(defaults, path);
    expect(second.data.selected, 16);
    expect(second.data.syncPending, isTrue);
    expect(second.pair(16)[0].name, first.data.tones[1].name);
  });

  test('parameters', () {
    final shift = defaults.params[102];
    expect(shift.steps, 49);
    expect(shift.snap(.51), .5);
    expect(shift.snap(.76), closeTo(.75, 1e-6));
    expect(defaults.params[14].display(1), 'METAL');
    expect(toneRef(33), 129);
    expect(refTone(129), 33);
  });

  test('level log', () {
    final lg = LevelLog('${temp.path}/levels.csv');
    final t0 = DateTime(2026, 9, 24, 20);
    LevelSession s(int id, int dur, int since, bool active, [int outClips = 2]) =>
        LevelSession(id: id, inMax: .5, inAvg: .1, outMax: .3, inClips: 0, outClips: outClips, durationMs: dur, sinceMs: since, active: active);
    expect(lg.observe(s(1, 60000, 0, true), 'guitar', 'A', t0), isNull);
    final e1 = lg.observe(s(1, 60000, 5000, false), 'guitar', 'A', t0)!;
    expect(e1.inMaxDb, closeTo(-6.02, .05));
    expect(e1.inAvgDb, closeTo(-20, .05));
    expect(e1.end, t0.subtract(const Duration(seconds: 5)));
    expect(lg.observe(s(1, 60000, 9000, false), 'guitar', 'A', t0.add(const Duration(seconds: 4))), isNull);
    expect(lg.observe(s(2, 800, 1000, false, 0), 'guitar', 'A', t0), isNull);
    final re = LevelLog(lg.path);
    expect(re.entries.length, 1);
    expect(re.entries[0].rig, 'A');
    expect(re.entries[0].outClips, 2);
    expect(re.observe(s(1, 60000, 5000, false), 'guitar', 'A', t0), isNull);
  });

  test('tuner / meter / looper text', () {
    var r = analyseNote(82.41);
    expect([r.note, r.octave], ['E', 2]);
    expect(r.cents.abs(), lessThan(1));
    r = analyseNote(442, a4: 442);
    expect([r.note, r.octave], ['A', 4]);
    expect(r.cents.abs(), lessThan(.01));
    expect(analyseNote(440, a4: 442).cents, closeTo(-7.85, .01));
    expect(analyseNote(440, a4: 430).cents, closeTo(39.8, .1));
    r = analyseNote(30.87);
    expect([r.note, r.octave], ['B', 0]);
    expect(toDb(1), 0);
    expect(toDb(0), meterFloorDb);
    expect(toDb(.1), closeTo(-20, .01));
    final live = Uint8List(22)
      ..[0] = 1
      ..[1] = 2
      ..[2] = 2
      ..[3] = 50;
    final bd = ByteData.sublistView(live)
      ..setUint32(12, 48000, Endian.little)
      ..setUint32(16, 24000, Endian.little)
      ..setUint16(20, 60, Endian.little);
    expect(bd.lengthInBytes, 22);
    final st = LiveState.parse(live);
    expect(st.looperMode, isTrue);
    expect(st.levelPercent, 100);
    expect(st.describe(), '▶ PLAY  0.5 / 1.0 s');
    expect(st.trimGuitar, isNull);
    final live24 = Uint8List(24)
      ..setRange(0, 22, live)
      ..[22] = 30
      ..[23] = 22;
    final st24 = LiveState.parse(live24);
    expect(st24.trimGuitar, 6);
    expect(st24.trimBass, -2);
    expect(encodeCommand(Cmd.inputTrim, 6 + 24), [24, 30]);
  });
}
