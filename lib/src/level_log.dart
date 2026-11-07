// Level meter math, the per-session level log (levels.csv) and tuner note math.
import 'dart:io';
import 'dart:math' as math;

import 'protocol.dart';

const double meterFloorDb = -60;

double toDb(double peak) => peak <= 0 ? meterFloorDb : math.max(meterFloorDb, 20 * math.log(peak) / math.ln10);

/// Peak meter ballistics: fast attack, ~40 dB/s fall at 150 ms updates, 1.5 s hold, clip lamp above -1 dBFS.
class MeterBallistics {
  double level = meterFloorDb, hold = meterFloorDb;
  DateTime _holdAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime clipAt = DateTime.fromMillisecondsSinceEpoch(0);

  void push(double peak, DateTime now) {
    final db = toDb(peak);
    level = db > level ? db : math.max(db, level - 6);
    if (db >= hold || now.difference(_holdAt) > const Duration(milliseconds: 1500)) {
      hold = db;
      _holdAt = now;
    }
    if (db > -1) clipAt = now;
  }

  bool clipping(DateTime now) => now.difference(clipAt) < const Duration(seconds: 2);

  void clear() {
    level = hold = meterFloorDb;
    clipAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmt1(double v) => v.toStringAsFixed(1);

/// One playing session as measured by the pedal.
class LevelEntry {
  LevelEntry(this.end, this.duration, this.inMaxDb, this.inAvgDb, this.outMaxDb, this.inClips, this.outClips, this.mode, this.rig);
  final DateTime end;
  final Duration duration;
  final double inMaxDb, inAvgDb, outMaxDb;
  final int inClips, outClips;
  final String mode, rig;

  static const String csvHeader = 'end,duration_s,in_max_dbfs,in_avg_dbfs,out_max_dbfs,in_clip_blocks,out_clip_blocks,mode,rig';

  bool get clipped => inClips + outClips > 0;

  static String stamp(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  String toCsv() => [
        stamp(end),
        (duration.inMilliseconds / 1000).toStringAsFixed(1),
        _fmt1(inMaxDb),
        _fmt1(inAvgDb),
        _fmt1(outMaxDb),
        '$inClips',
        '$outClips',
        mode,
        '"${rig.replaceAll('"', '""')}"',
      ].join(',');

  static LevelEntry? fromCsv(String line) {
    try {
      final p = <String>[];
      final cur = StringBuffer();
      var q = false;
      for (final ch in line.split('')) {
        if (ch == '"') {
          q = !q;
          continue;
        }
        if (ch == ',' && !q) {
          p.add(cur.toString());
          cur.clear();
        } else {
          cur.write(ch);
        }
      }
      p.add(cur.toString());
      if (p.length < 9) return null;
      final dt = p[0].split(' ');
      final d = dt[0].split('-').map(int.parse).toList();
      final t = dt[1].split(':').map(int.parse).toList();
      return LevelEntry(
        DateTime(d[0], d[1], d[2], t[0], t[1], t[2]),
        Duration(milliseconds: (double.parse(p[1]) * 1000).round()),
        double.parse(p[2]),
        double.parse(p[3]),
        double.parse(p[4]),
        int.parse(p[5]),
        int.parse(p[6]),
        p[7],
        p[8],
      );
    } catch (_) {
      return null;
    }
  }

  String get durationText => '${duration.inMinutes}:${_two(duration.inSeconds % 60)}';
  String get endText => '${_two(end.month)}/${_two(end.day)} ${_two(end.hour)}:${_two(end.minute)}';
}

/// Keeps a CSV log of recent playing sessions and dedupes the pedal's session reports,
/// which repeat on every status read.
class LevelLog {
  LevelLog(this.path) {
    try {
      final f = File(path);
      if (f.existsSync()) {
        for (final l in f.readAsLinesSync().skip(1)) {
          final e = LevelEntry.fromCsv(l);
          if (e != null) entries.add(e);
        }
      }
    } catch (_) {}
  }

  static const int keep = 200;
  final String path;
  final List<LevelEntry> entries = [];
  String _lastKey = '';

  /// Feed every session report; returns the entry when a finished session is logged.
  LevelEntry? observe(LevelSession s, String mode, String rig, DateTime now) {
    final key = '${s.id}:${s.durationMs}'; // id restarts when the pedal is powered off
    if (s.active || key == _lastKey) return null;
    _lastKey = key;
    if (s.durationMs < 2000) return null; // ignore bumps and single plucks
    final e = LevelEntry(now.subtract(Duration(milliseconds: s.sinceMs)), Duration(milliseconds: s.durationMs), toDb(s.inMax), toDb(s.inAvg), toDb(s.outMax),
        s.inClips, s.outClips, mode, rig);
    // skip a session already logged (pedal counter restart / app restart)
    if (entries.any((x) => x.end.difference(e.end).inMilliseconds.abs() < 5000 && (x.duration - e.duration).inMilliseconds.abs() < 1000)) return null;
    entries.add(e);
    if (entries.length > keep) entries.removeRange(0, entries.length - keep);
    try {
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync([LevelEntry.csvHeader, ...entries.map((x) => x.toCsv())].join('\n'));
    } catch (_) {}
    return e;
  }
}

class TunerReading {
  const TunerReading(this.note, this.octave, this.cents);
  final String note;
  final int octave;
  final double cents;
}

const List<String> noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

TunerReading analyseNote(double hz, {double a4 = 440}) {
  final midi = 69 + 12 * (math.log(hz / a4) / math.ln2);
  final n = midi.round();
  return TunerReading(noteNames[((n % 12) + 12) % 12], n ~/ 12 - 1, (midi - n) * 100);
}
