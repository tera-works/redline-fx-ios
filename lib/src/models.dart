// Tones, RIG library and parameter table (port of the .NET Models.cs).
// Settings file format "redline-fx-settings" v7 (v6 + preset v8 type lists).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class LibraryException implements Exception {
  LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Shortest decimal that survives a float32 round trip (keeps library.json readable).
double _short(double v) => double.parse(v.toStringAsPrecision(7));

class Tone {
  Tone({required this.name, required List<double> values, this.irSlot = -1})
      : values = Float32List.fromList(values);

  // Preset layout v8 (firmware FX_PRESET_VERSION 8): 107 normalised values.
  static const int paramCount = 107, v6ParamCount = 106, v5ParamCount = 97, v4ParamCount = 88, legacyParamCount = 66;
  static const int driveTypeId = 14, modTypeId = 21, reverbTypeId = 36, cabModelId = 43, delayTypeId = 65, ampTypeId = 89, currentVersion = 8;
  static int get encodedLength => 1 + 24 + paramCount * 4 + 4; // 457
  static int encodedLengthFor(int count) => 1 + 24 + count * 4 + 4;

  // Defaults of parameters added after v3 (match fill_default() in fx_chain.c).
  static const List<double> v4Defaults = [0, .5, .5, .5, .5, .5, .5, .5, .5, 0, 6 / 14, 3 / 31, .6, 1, 12 / 18, 0, 80 / 200, 1, 0, .5, 1, 2.5 / 19.5];
  static const List<double> v5Defaults = [0, .5, .5, .5, .5, .5, .5, .5, 24 / 30];
  static const List<double> v6Defaults = [0, .5, 490 / 1990, .5, 0, .75, .5, .5, .8];
  static const List<double> v7Defaults = [0];
  // v7 grew three enums; keep the chosen index. (id, steps before v7, steps in v7)
  static const List<List<int>> v7Enums = [
    [modTypeId, 3, 5],
    [cabModelId, 3, 5],
    [ampTypeId, 3, 4],
  ];
  // v8 (same length as v7): Mod + ROTARY/RING MOD, Delay + REVERSE, Reverb + SHIMMER.
  static const List<List<int>> v8Enums = [
    [modTypeId, 5, 7],
    [delayTypeId, 3, 4],
    [reverbTypeId, 3, 4],
  ];

  String name;
  final Float32List values;
  int irSlot;

  Tone copy() => Tone(name: name, values: values, irSlot: irSlot);

  static double restep(double n, int from, int to) => (_clamp01(n) * (from - 1)).round() / (to - 1);
  static double driveTypeFromV3(double n) => (_clamp01(n) * 2).round() / 3;
  static double driveTypeToV3(double n) {
    var i = (_clamp01(n) * 3).round();
    if (i == 3) i = 1; // METAL -> DIST
    return i / 2;
  }

  /// Value of parameter [id] read from an older tone format (settings migration).
  static double fromOldFormat(int id, double n, int version) {
    if (version >= currentVersion) return n;
    if (version < 7) {
      if (id == driveTypeId && version == 3) n = driveTypeFromV3(n);
      for (final e in v7Enums) {
        if (id == e[0]) n = restep(n, e[1], e[2]);
      }
    }
    for (final e in v8Enums) {
      if (id == e[0]) n = restep(n, e[1], e[2]);
    }
    return n;
  }

  /// v7 tone values (same length) -> v8.
  static List<double> fromV7(List<double> v) => [for (var i = 0; i < v.length; i++) fromOldFormat(i, v[i], 7)];

  /// Value of parameter [id] in an older tone format (test helper for the migration).
  static double toOldFormat(int id, double n, int version) {
    if (version >= currentVersion) return n;
    for (final e in v8Enums) {
      if (id != e[0]) continue;
      var i = (_clamp01(n) * (e[2] - 1)).round();
      if (id == modTypeId) {
        i = i == 5 ? 4 : (i == 6 ? 3 : i); // ROTARY->VIBE, RING->TREMOLO
      } else {
        i = i == 3 ? (id == reverbTypeId ? 1 : 0) : i; // SHIMMER->HALL, REVERSE->DIGITAL
      }
      n = i / (e[1] - 1);
    }
    if (version >= 7) return n;
    if (id == driveTypeId && version == 3) return driveTypeToV3(n);
    for (final e in v7Enums) {
      if (id != e[0]) continue;
      var i = (_clamp01(n) * (e[2] - 1)).round();
      if (id == modTypeId) {
        i = i == 3 ? 1 : (i == 4 ? 2 : i); // TREM->CHORUS, VIBE->PHASER
      } else if (id == cabModelId) {
        i = i == 3 ? 0 : (i == 4 ? 2 : i); // 8x10->4x12, 1x15->1x12
      } else {
        i = i == 3 ? 0 : i; // BASS amp -> CLEAN
      }
      return i / (e[1] - 1);
    }
    return n;
  }

  /// 66 / 88 / 97 / 106 values (older settings files) -> 107 values.
  static List<double> upgradeValues(List<double> input) {
    var v = List<double>.of(input);
    if (v.length == paramCount) return v;
    if (v.length == legacyParamCount) {
      v[driveTypeId] = driveTypeFromV3(v[driveTypeId]);
      v = [...v, ...v4Defaults];
    }
    if (v.length == v4ParamCount) v = [...v, ...v5Defaults];
    if (v.length == v5ParamCount) v = [...v, ...v6Defaults];
    if (v.length != v6ParamCount) throw LibraryException('音色データが不正です');
    v = [...v, ...v7Defaults];
    for (final e in v7Enums) {
      v[e[0]] = restep(v[e[0]], e[1], e[2]);
    }
    return fromV7(v);
  }

  void validate() {
    final n = utf8.encode(name).length;
    if (n < 1 || n > 23 || values.length != paramCount || irSlot < -1 || irSlot > 3 || values.any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw LibraryException('音色データが不正です');
    }
  }

  Uint8List encode() {
    validate();
    final b = Uint8List(encodedLength);
    final d = ByteData.sublistView(b);
    b[0] = currentVersion;
    b.setRange(1, 1 + utf8.encode(name).length, utf8.encode(name));
    for (var i = 0; i < paramCount; i++) {
      d.setFloat32(25 + i * 4, values[i], Endian.little);
    }
    d.setInt8(25 + paramCount * 4, irSlot);
    return b;
  }

  static Tone decode(Uint8List b) {
    if (b.length != encodedLength || (b[0] != currentVersion && b[0] != 7)) {
      throw LibraryException('本体のファームウェアが古いか、音色形式が違います。最新ファームウェアを書き込んでください');
    }
    final d = ByteData.sublistView(b);
    final raw = b.sublist(1, 25);
    final end = raw.indexOf(0);
    final name = utf8.decode(end < 0 ? raw : raw.sublist(0, end), allowMalformed: true);
    final values = List<double>.generate(paramCount, (i) => d.getFloat32(25 + i * 4, Endian.little));
    final t = Tone(
      name: name,
      values: b[0] == 7 ? fromV7(values) : values, // v7 firmware: same layout, fewer types
      irSlot: d.getInt8(25 + paramCount * 4),
    );
    t.validate();
    return t;
  }

  factory Tone.fromJson(Map<String, dynamic> j) => Tone(
        name: j['name'] as String? ?? '',
        values: (j['values'] as List).map((e) => (e as num).toDouble()).toList(),
        irSlot: (j['ir_slot'] as num?)?.toInt() ?? -1,
      );

  /// Settings files v2..v5 keep 66..106 values ([upgradeValues] fixes the length);
  /// v6 keeps 107 values with the v7 type lists.
  factory Tone.fromJsonUpgrading(Map<String, dynamic> j, int fileVersion) {
    final raw = (j['values'] as List).map((e) => (e as num).toDouble()).toList();
    final values = fileVersion >= 2 && fileVersion <= 5 ? upgradeValues(raw) : (fileVersion == 6 && raw.length == paramCount ? fromV7(raw) : raw);
    return Tone(name: j['name'] as String? ?? '', values: values, irSlot: (j['ir_slot'] as num?)?.toInt() ?? -1);
  }

  Map<String, dynamic> toJson() => {'name': name, 'values': values.map(_short).toList(), 'ir_slot': irSlot};
}

class LibraryData {
  LibraryData({
    this.format = 'redline-fx-settings',
    this.version = 7,
    this.mode = 'guitar',
    this.stash,
    required this.tones,
    required this.combinations,
    this.selected = 3,
    required this.combinationTones,
    this.syncPending = false,
  });

  String format;
  int version;
  String mode; // "guitar" | "bass": which bank is active
  LibraryData? stash; // the other mode's bank (null = factory defaults)
  List<Tone> tones;
  List<List<int>> combinations;
  int selected;
  List<List<Tone>?> combinationTones;
  bool syncPending;

  static const int toneCount = 48, factoryToneCount = 32, rigCount = 32;

  factory LibraryData.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] as num?)?.toInt() ?? 0;
    Tone t(dynamic e) => Tone.fromJsonUpgrading(e as Map<String, dynamic>, version);
    final ct = (j['combination_tones'] as List?) ?? const [];
    return LibraryData(
      format: j['format'] as String? ?? '',
      version: version,
      mode: j['mode'] as String? ?? 'guitar',
      stash: j['stash'] == null ? null : LibraryData.fromJson(j['stash'] as Map<String, dynamic>),
      tones: ((j['tones'] as List?) ?? const []).map(t).toList(),
      combinations: ((j['combinations'] as List?) ?? const []).map((p) => (p as List).map((e) => (e as num).toInt()).toList()).toList(),
      selected: (j['selected'] as num?)?.toInt() ?? 0,
      combinationTones: List<List<Tone>?>.generate(
        ct.isEmpty ? rigCount : ct.length,
        (i) => i < ct.length && ct[i] != null ? (ct[i] as List).map(t).toList() : null,
      ),
      syncPending: j['sync_pending'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'mode': mode,
        'stash': stash?.toJson(),
        'tones': tones.map((t) => t.toJson()).toList(),
        'combinations': combinations,
        'selected': selected,
        'combination_tones': combinationTones.map((p) => p?.map((t) => t.toJson()).toList()).toList(),
        'sync_pending': syncPending,
      };

  LibraryData clone() => LibraryData.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  /// v2..v6 -> v7 (values were already upgraded while parsing).
  bool migrate() {
    if (version < 2 || version > 6) return false;
    if (version <= 5) {
      mode = 'guitar';
      stash = null;
    }
    stash?.migrate();
    version = 7;
    return true;
  }

  void validate() {
    if (mode != 'guitar' && mode != 'bass') throw LibraryException('モードが不正です');
    final s = stash;
    if (s != null) {
      if (s.stash != null || s.mode == mode) throw LibraryException('モード別の設定が不正です');
      s.validate();
    }
    if (format != 'redline-fx-settings' || version != 7 || tones.length != toneCount || combinations.length != rigCount || selected < 0 || selected >= rigCount) {
      throw LibraryException('設定ファイルの形式が未対応です（v7が必要です）');
    }
    for (final t in tones) {
      t.validate();
    }
    if (combinations.any((p) => p.length != 2 || p.any((i) => i < 0 || i >= toneCount))) throw LibraryException('組み合わせが不正です');
    if (combinationTones.length != rigCount) throw LibraryException('組み合わせ音色が不正です');
    for (final p in combinationTones) {
      if (p == null) continue;
      if (p.length != 2) throw LibraryException('組み合わせ音色が不正です');
      for (final t in p) {
        t.validate();
      }
    }
  }
}

class Parameter {
  Parameter({
    required this.id,
    required this.block,
    required this.name,
    required this.label,
    required this.minimum,
    required this.maximum,
    required this.control,
    required this.unit,
    required this.choices,
    this.steps = 0,
  });
  final int id, block;
  final String name, label, control, unit; // control: bool / enum / knob / fader
  final double minimum, maximum;
  final List<String> choices;
  final int steps; // >1: snaps to this many positions (e.g. Pitch Shift semitones)

  factory Parameter.fromJson(Map<String, dynamic> j) => Parameter(
        id: (j['id'] as num).toInt(),
        block: (j['block'] as num).toInt(),
        name: j['name'] as String? ?? '',
        label: j['label'] as String? ?? '',
        minimum: (j['minimum'] as num).toDouble(),
        maximum: (j['maximum'] as num).toDouble(),
        control: j['control'] as String? ?? 'knob',
        unit: j['unit'] as String? ?? '',
        choices: ((j['choices'] as List?) ?? const []).map((e) => e as String).toList(),
        steps: (j['steps'] as num?)?.toInt() ?? 0,
      );

  bool get isBool => control == 'bool';
  bool get isEnum => control == 'enum';
  bool get isFader => control == 'fader';

  double snap(double n) => steps > 1 ? (_clamp01(n) * (steps - 1)).round() / (steps - 1) : n;

  int choiceIndex(double n) => math.max(0, math.min(choices.length - 1, (n * maximum).round()));

  String display(double n) {
    if (isBool) return n > .5 ? 'ON' : 'OFF';
    if (isEnum) return choices.isEmpty ? '' : choices[choiceIndex(n)];
    final v = minimum + n * (maximum - minimum);
    if (unit == '%') return '${(v * 100).round()}%';
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    if (s == '-0') s = '0';
    return unit.isEmpty ? s : '$s $unit';
  }
}

class Defaults {
  Defaults({
    required this.library,
    required this.bassLibrary,
    required this.params,
    required this.pairs,
    required this.bassPairs,
    required this.blocks,
    required this.blockOrder,
  });
  final LibraryData library, bassLibrary;
  final List<Parameter> params;
  final List<String> pairs, bassPairs, blocks;
  final List<int> blockOrder;

  factory Defaults.parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    List<String> strings(String k) => ((j[k] as List?) ?? const []).map((e) => e as String).toList();
    return Defaults(
      library: LibraryData.fromJson(j['library'] as Map<String, dynamic>),
      bassLibrary: LibraryData.fromJson(j['bass_library'] as Map<String, dynamic>),
      params: (j['params'] as List).map((e) => Parameter.fromJson(e as Map<String, dynamic>)).toList(),
      pairs: strings('pairs'),
      bassPairs: strings('bass_pairs'),
      blocks: strings('blocks'),
      blockOrder: ((j['block_order'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
    );
  }

  LibraryData libraryFor(String mode) => mode == 'bass' ? bassLibrary : library;
  List<String> pairsFor(String mode) => mode == 'bass' ? bassPairs : pairs;
  List<int> get order => blockOrder.length == blocks.length ? blockOrder : List<int>.generate(blocks.length, (i) => i);
  List<Parameter> paramsOf(int block) => params.where((p) => p.block == block).toList();

  /// The block's on/off switch, if it has one.
  Parameter? enableOf(int block) {
    for (final p in params) {
      if (p.block == block && p.isBool) return p;
    }
    return null;
  }
}

/// Tone slot index (0..47) -> reference byte sent with a slot (factory 0..31, user 128..143).
int toneRef(int i) => i < 32 ? i : 128 + i - 32;
int refTone(int r) => r < 32 ? r : (r >= 128 && r < 144 ? r - 128 + 32 : 0);

/// The settings file (both guitar and bass banks) and its persistence.
class Library {
  Library(this.defaults, this.path, this.data);

  final Defaults defaults;
  final String path;
  LibraryData data;

  static const JsonEncoder json = JsonEncoder.withIndent('  ');

  /// Loads [path] (or the factory library when it does not exist).
  static Library open(Defaults defaults, String path) {
    final file = File(path);
    var data = defaults.library.clone();
    if (file.existsSync()) {
      data = LibraryData.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      final oldVersion = data.version;
      if (data.migrate()) {
        final backup = File('$path.v$oldVersion-backup.json');
        if (!backup.existsSync()) file.copySync(backup.path);
        data.validate();
        final lib = Library(defaults, path, data);
        lib.save();
        return lib;
      }
      data.validate();
    }
    return Library(defaults, path, data);
  }

  void save() {
    data.validate();
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.flutter.tmp');
    tmp.writeAsStringSync(json.convert(data.toJson()), flush: true);
    tmp.renameSync(path);
  }

  String exportJson() => json.convert(data.toJson());

  void importJson(String text) {
    final d = LibraryData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    d.migrate();
    d.validate();
    data = d;
    save();
  }

  /// Resets both banks to factory; stays in the current mode.
  void reset() {
    final mode = data.mode;
    data = defaults.libraryFor(mode).clone()
      ..mode = mode
      ..stash = null
      ..syncPending = true;
    save();
  }

  bool get bass => data.mode == 'bass';
  LibraryData get defaultLibrary => defaults.libraryFor(data.mode);
  List<String> get pairs => defaults.pairsFor(data.mode);
  String rigName(int i) => pairs[i].split('  //')[0];
  String rigSubtitle(int i) {
    final parts = pairs[i].split('  //');
    return parts.length > 1 ? parts[1].trim() : '';
  }

  /// Swap the whole preset library (tones + RIGs) to the other instrument.
  void switchMode(String mode) {
    if (mode != 'guitar' && mode != 'bass') throw LibraryException('モードが不正です');
    if (data.mode == mode) return;
    final current = data.clone()..stash = null;
    final next = data.stash != null ? data.stash!.clone() : defaults.libraryFor(mode).clone();
    next
      ..mode = mode
      ..stash = current
      ..syncPending = true;
    data = next;
    save();
  }

  List<Tone> pair(int index) =>
      data.combinationTones[index]?.map((t) => t.copy()).toList() ?? data.combinations[index].map((i) => data.tones[i].copy()).toList();

  void storePair(List<Tone> pair, List<int> indices) {
    if (pair.length != 2 || indices.length != 2) throw LibraryException('組み合わせが不正です');
    for (final t in pair) {
      t.validate();
    }
    data.combinations[data.selected] = List<int>.of(indices);
    data.combinationTones[data.selected] = pair.map((t) => t.copy()).toList();
    data.syncPending = true;
    save();
  }
}
