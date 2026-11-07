// App state and pedal logic (port of the .NET App.cs editor logic, UI-free).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'ble_link.dart';
import 'level_log.dart';
import 'models.dart';
import 'protocol.dart';

enum LinkState { idle, scanning, connecting, connected, error }

/// Where library.json / levels.csv live. Portable mode (portable.flag next to the exe)
/// and the .NET app's files are honoured on Windows.
class StoragePaths {
  StoragePaths(this.library, this.levels);
  final String library, levels;

  static Future<StoragePaths> resolve() async {
    if (!kIsWeb && Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (File('$exeDir\\portable.flag').existsSync()) {
        return StoragePaths('$exeDir\\data\\library.json', '$exeDir\\data\\levels.csv');
      }
    }
    final dir = (await getApplicationSupportDirectory()).path;
    final sep = Platform.pathSeparator;
    final paths = StoragePaths('$dir${sep}library.json', '$dir${sep}levels.csv');
    if (Platform.isWindows) paths._adoptDotNetFiles();
    return paths;
  }

  /// First start on a PC that used the .NET app: take over its settings and level log.
  void _adoptDotNetFiles() {
    final env = Platform.environment;
    void adopt(String? base, String name, String target) {
      if (base == null || File(target).existsSync()) return;
      final src = File('$base\\RedlineFX\\$name');
      if (!src.existsSync()) return;
      try {
        File(target).parent.createSync(recursive: true);
        src.copySync(target);
      } catch (_) {}
    }

    adopt(env['APPDATA'], 'library.json', library);
    adopt(env['LOCALAPPDATA'], 'levels.csv', levels);
  }
}

/// Level meters change every 150 ms; kept apart so the whole UI does not rebuild.
class MeterModel extends ChangeNotifier {
  final input = MeterBallistics();
  final output = MeterBallistics();
  LevelSession? session; // current or last session reported by the pedal

  void update() => notifyListeners();

  void clear() {
    input.clear();
    output.clear();
    notifyListeners();
  }
}

class PedalController extends ChangeNotifier {
  PedalController._(this.defaults, this.library, this.levelLog, {required this.autoSearch, String? tunerPath}) : _tunerPath = tunerPath {
    tunerA4 = _loadTunerA4();
    active = library.pair(library.data.selected);
    references = library.data.combinations[library.data.selected].map(toneRef).toList();
    selectedBlock = defaults.order.first;
    _subs.add(link.found.listen(_onFound));
    _subs.add(link.connectionChanges.listen((c) {
      if (!c) _lost();
    }));
  }

  static Future<PedalController> create({bool autoSearch = true}) async {
    final defaults = Defaults.parse(await rootBundle.loadString('assets/defaults.json'));
    final paths = await StoragePaths.resolve();
    Library library;
    String? loadError;
    try {
      library = Library.open(defaults, paths.library);
    } catch (e) {
      // keep the unreadable file for the user and start from factory data
      loadError = '設定ファイルを読み込めませんでした（$e）。初期設定で起動します';
      try {
        File(paths.library).renameSync('${paths.library}.broken-${DateTime.now().millisecondsSinceEpoch}.json');
      } catch (_) {}
      library = Library.open(defaults, paths.library);
    }
    final tunerPath = '${File(paths.library).parent.path}${Platform.pathSeparator}tuner.txt';
    final c = PedalController._(defaults, library, LevelLog(paths.levels), autoSearch: autoSearch, tunerPath: tunerPath);
    if (loadError != null) c.status = loadError;
    return c;
  }

  final Defaults defaults;
  final Library library;
  final LevelLog levelLog;
  final bool autoSearch;
  final link = PedalLink();
  final meters = MeterModel();
  final _subs = <StreamSubscription<dynamic>>[];
  final _errors = StreamController<String>.broadcast();

  /// Errors to show once (snackbar / dialog).
  Stream<String> get errors => _errors.stream;

  LinkState linkState = LinkState.idle;
  String linkError = '';
  final List<NearbyDevice> devices = [];
  String? selectedDevice;

  late List<Tone> active; // [OFF, ON] tones being edited
  late List<int> references; // slot reference bytes (factory 0..31, user 128..143)
  int side = 0; // tone being edited: 0 OFF, 1 ON
  late int selectedBlock;
  bool? pressed; // sounding side reported by the pedal (null = unknown)
  bool? physical; // footswitch position
  double? dspLoad;
  int? oversampling;
  LiveState? live;
  String status = '';
  int tonePage = 0, rigPage = 0;
  bool busy = false;

  // tuner
  bool tunerOpen = false;
  LiveState? tunerLive;
  double? tunerCents;
  double tunerA4 = tunerA4Default; // reference pitch, saved in tuner.txt
  final String? _tunerPath;
  static const double tunerA4Default = 440, tunerA4Min = 430, tunerA4Max = 450;
  DateTime _tunerOpened = DateTime.now();
  Timer? _tunerTimer;
  bool _tunerReading = false;

  // looper level (slider is local while dragging)
  int? loopLevelOverride;
  Timer? _loopLevelTimer, _loopLevelEndTimer;

  final Map<int, double> _pending = {}; // key side*256+id
  Timer? _pollTimer, _flushTimer, _meterTimer;
  bool _polling = false, _flushing = false, _metering = false, _disposed = false;
  DateTime _nextSearch = DateTime.fromMillisecondsSinceEpoch(0);

  bool get connected => link.connected && linkState == LinkState.connected;
  bool get bass => library.bass;
  int get selectedTone => refTone(references[side]);
  int get soundingSide => pressed == true ? 1 : 0;
  String get rigName => library.rigName(library.data.selected);

  void start() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _pollTick());
    _flushTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!busy && !_flushing) _flush().catchError((Object e) => _report(e));
    });
    _meterTimer = Timer.periodic(const Duration(milliseconds: 150), (_) => _meterTick());
    _ensureSearch();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
      paramTick.value++;
    }
  }

  /// Ticks on every parameter edit. Knob drags only tick this (the faceplate listens to it),
  /// so the rest of the screen is not rebuilt on every drag event.
  final ValueNotifier<int> paramTick = ValueNotifier<int>(0);

  bool _isEnableParam(Parameter p) => defaults.order.any((b) => defaults.enableOf(b)?.id == p.id);

  void _report(Object e) {
    if (!_errors.isClosed) _errors.add(e.toString());
  }

  /// Runs a user action; one at a time, errors are reported.
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      await action();
    } catch (e) {
      if (linkState == LinkState.connecting || linkState == LinkState.scanning) {
        linkState = LinkState.error;
        linkError = e.toString();
      }
      _report(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void _requireConnection() {
    if (!connected) throw BleException('本体に接続してください');
  }

  // ---------------------------------------------------------------- Bluetooth
  void _onFound(NearbyDevice d) {
    final i = devices.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      if (devices[i].name == d.name) return;
      devices[i] = d;
    } else {
      devices.add(d);
    }
    selectedDevice ??= d.id;
    _notify();
  }

  void selectDevice(String id) {
    selectedDevice = id;
    _notify();
  }

  Future<void> _ensureSearch() async {
    if (!autoSearch || busy || link.connected || link.scanning || DateTime.now().isBefore(_nextSearch)) return;
    _nextSearch = DateTime.now().add(const Duration(seconds: 10));
    try {
      await link.startScan();
      linkState = LinkState.scanning;
      linkError = '';
    } catch (e) {
      linkState = LinkState.error;
      linkError = e.toString();
    }
    _notify();
  }

  /// Search again right now (after an error, or when the list is empty).
  Future<void> rescan() async {
    await link.stopScan();
    devices.clear();
    selectedDevice = null;
    _nextSearch = DateTime.fromMillisecondsSinceEpoch(0);
    await _ensureSearch();
  }

  Future<void> connect() => run(() async {
        final id = selectedDevice;
        if (id == null) throw BleException('本体が検出されるまでお待ちください');
        linkState = LinkState.connecting;
        _notify();
        await link.connect(id);
        await link.bassMode(library.bass);
        if (library.data.syncPending) {
          _reloadRig();
          await _sendPair();
        } else {
          active = await link.readPair();
          references = List<int>.of(link.references);
          _rebase();
        }
        final sw = await link.readSwitch();
        pressed = sw.pressed;
        physical = sw.physical;
        side = sw.pressed ? 1 : 0;
        linkState = LinkState.connected;
        linkError = '';
        status = '';
        live = await link.readLive();
      });

  Future<void> disconnect() async {
    await closeTuner();
    await link.disconnect();
    _lost();
  }

  void _lost() {
    if (linkState == LinkState.connected || linkState == LinkState.connecting) linkState = LinkState.idle;
    pressed = null;
    physical = null;
    dspLoad = null;
    live = null;
    _pending.clear();
    meters.clear();
    if (tunerOpen) {
      tunerOpen = false;
      _tunerTimer?.cancel();
    }
    _notify();
  }

  Future<void> _pollTick() async {
    if (busy || _polling) return;
    if (!link.connected) {
      if (linkState == LinkState.connected) _lost();
      await _ensureSearch();
      return;
    }
    _polling = true;
    try {
      await link.stopScan();
      final before = _pollSignature();
      final sw = await link.readSwitch();
      physical = sw.physical;
      final l = await link.readLive();
      live = l;
      if (pressed != sw.pressed) {
        await _flush();
        pressed = sw.pressed;
      }
      // rebuild the screen only when something visible changed (keeps animations smooth)
      if (_pollSignature() != before) _notify();
    } catch (_) {
      physical = null;
      _notify();
    } finally {
      _polling = false;
    }
  }

  String _pollSignature() {
    final l = live;
    final loop = l == null
        ? ''
        : '${l.tunerOn}${l.looperMode}${l.bassMode}${l.loopState}${l.levelPercent}${l.length ~/ 4800}${l.position ~/ 4800}${l.trimGuitar}${l.trimBass}';
    return '$physical$pressed${dspLoad?.round()}$loop';
  }

  Future<void> _meterTick() async {
    if (_metering || busy || !connected) return;
    _metering = true;
    try {
      final (st, lv) = await link.readStatus();
      dspLoad = st.dspLoad;
      oversampling = st.oversampling;
      final now = DateTime.now();
      meters.input.push(lv.inPeak, now);
      meters.output.push(lv.outPeak, now);
      final s = lv.session;
      if (s != null) {
        if (levelLog.observe(s, library.data.mode, rigName, now) != null || s.active) meters.session = s;
      }
      meters.update();
    } catch (_) {
    } finally {
      _metering = false;
    }
  }

  // ---------------------------------------------------------------- editing
  Future<void> _flush() async {
    while (_flushing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_pending.isEmpty) return;
    _flushing = true;
    try {
      if (!link.connected) {
        _pending.clear();
        return;
      }
      final sounding = (await link.readSwitch()).pressed ? 1 : 0;
      final items = Map<int, double>.of(_pending);
      _pending.clear();
      for (final e in items.entries) {
        if (e.key ~/ 256 == sounding) await link.param(e.key % 256, e.value);
      }
    } finally {
      _flushing = false;
    }
  }

  double value(int id) => active[side].values[id];

  void setParam(Parameter p, double n) {
    n = p.snap(n < 0 ? 0 : (n > 1 ? 1 : n));
    if (active[side].values[p.id] == n) return;
    final coarse = status.isNotEmpty || _isEnableParam(p);
    final wasDirty = coarse ? false : rigDirty;
    active[side].values[p.id] = n;
    status = '';
    if (connected && pressed != null && side == soundingSide) _pending[side * 256 + p.id] = n;
    if (coarse || rigDirty != wasDirty) {
      _notify();
    } else if (!_disposed) {
      paramTick.value++;
    }
  }

  // Each side's tone as it was loaded / saved: the reference for "edited" marks and revert.
  late List<Tone> _base = [active[0].copy(), active[1].copy()];
  void _rebase() => _base = [active[0].copy(), active[1].copy()];

  /// Value of a parameter as loaded (RIG / tone) or last saved, on the side being edited.
  double storedValue(int id) => _base[side].values[id];

  /// true when the knob was turned since the tone was loaded / saved.
  bool paramEdited(Parameter p) => (value(p.id) - storedValue(p.id)).abs() > 1e-6;

  /// true when any parameter of [block] was changed (marker on the pedal).
  bool blockEdited(int block) => defaults.paramsOf(block).any(paramEdited);

  /// true when the side being edited has changes that loading a tone would throw away.
  bool get sideEdited {
    final a = active[side].values, b = _base[side].values;
    for (var k = 0; k < a.length && k < b.length; k++) {
      if ((a[k] - b[k]).abs() > 1e-6) return true;
    }
    return false;
  }

  /// Back to the loaded value (double-click on a control).
  void revertParam(Parameter p) => setParam(p, storedValue(p.id));

  bool blockEnabled(int block) {
    final on = defaults.enableOf(block);
    return on != null && active[side].values[on.id] > .5;
  }

  void toggleBlock(int block) {
    final on = defaults.enableOf(block);
    if (on != null) setParam(on, blockEnabled(block) ? 0 : 1);
  }

  void selectBlock(int block) {
    selectedBlock = block;
    _notify();
  }

  void selectSide(int s) {
    side = s;
    _notify();
  }

  /// true when the tones being edited differ from the stored RIG.
  bool get rigDirty {
    final stored = library.pair(library.data.selected);
    final idx = library.data.combinations[library.data.selected];
    for (var i = 0; i < 2; i++) {
      if (refTone(references[i]) != idx[i] || stored[i].name != active[i].name) return true;
      for (var k = 0; k < Tone.paramCount; k++) {
        if (stored[i].values[k] != active[i].values[k]) return true;
      }
    }
    return false;
  }

  Future<void> _sendPair() async {
    _requireConnectionLink();
    await _flush();
    await link.assign(active, references);
    library.data.syncPending = false;
    library.save();
    status = '';
  }

  void _requireConnectionLink() {
    if (!link.connected) throw BleException('本体に接続してください');
  }

  void _reloadRig() {
    active = library.pair(library.data.selected);
    references = library.data.combinations[library.data.selected].map(toneRef).toList();
    _rebase();
  }

  Future<void> saveRig() => run(() async {
        library.storePair(active, references.map(refTone).toList());
        _rebase();
        if (connected) {
          await _sendPair();
        } else {
          status = '保存しました。次回接続時に本体へ書き込みます';
        }
      });

  Future<void> selectRig(int index) => run(() async {
        await _flush();
        library.data.selected = index;
        _reloadRig();
        library.data.syncPending = true;
        library.save();
        _notify();
        if (connected) {
          await _sendPair();
        } else {
          status = '次回接続時に本体へ書き込みます';
        }
      });

  /// Put a stored tone on the side being edited (sent with SAVE RIG).
  void loadTone(int index) {
    active[side] = library.data.tones[index].copy();
    references[side] = toneRef(index);
    _base[side] = active[side].copy();
    status = '';
    _notify();
  }

  void overwriteTone() {
    final i = selectedTone;
    library.data.tones[i] = active[side].copy()..name = library.defaultLibrary.tones[i].name;
    _base[side] = active[side].copy();
    library.save();
    _notify();
  }

  void resetTone() {
    final i = selectedTone;
    library.data.tones[i] = library.defaultLibrary.tones[i].copy();
    library.save();
    _notify();
  }

  Future<void> switchInstrument() => run(() async {
        await _flush();
        _pending.clear();
        library.switchMode(library.bass ? 'guitar' : 'bass');
        tonePage = rigPage = 0;
        _reloadRig();
        _notify();
        if (connected) {
          await link.bassMode(library.bass);
          await _sendPair();
        }
      });

  String exportJson() => library.exportJson();

  Future<void> importJson(String text) => run(() async {
        library.importJson(text);
        _reloadRig();
        if (connected) await link.bassMode(library.bass);
      });

  Future<void> resetLibrary() => run(() async {
        library.reset();
        _reloadRig();
      });

  void setPage({int? tone, int? rig}) {
    if (tone != null) tonePage = tone < 0 ? 0 : tone;
    if (rig != null) rigPage = rig < 0 ? 0 : rig;
    _notify();
  }

  // ---------------------------------------------------------------- live tools
  Future<void> openTuner() => run(() async {
        _requireConnection();
        await link.tuner(true);
        _tunerOpened = DateTime.now();
        tunerOpen = true;
        tunerLive = null;
        tunerCents = null;
        _tunerTimer?.cancel();
        _tunerTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tunerTick());
      });

  Future<void> _tunerTick() async {
    if (_tunerReading || !tunerOpen) return;
    _tunerReading = true;
    try {
      if (!link.connected) {
        await closeTuner();
        return;
      }
      final l = await link.readLive();
      // a stomp on the pedal leaves the tuner
      if (!l.tunerOn && DateTime.now().difference(_tunerOpened) > const Duration(seconds: 1)) {
        await closeTuner(sendOff: false);
        return;
      }
      tunerLive = l;
      if (l.hz <= 0 || l.clarity < .5) {
        tunerCents = null;
      } else {
        final c = analyseNote(l.hz, a4: tunerA4).cents;
        final prev = tunerCents;
        tunerCents = prev == null || (c - prev).abs() > 20 ? c : prev * .6 + c * .4;
      }
      _notify();
    } catch (_) {
    } finally {
      _tunerReading = false;
    }
  }

  double _loadTunerA4() {
    try {
      final p = _tunerPath;
      if (p != null && File(p).existsSync()) {
        final v = double.tryParse(File(p).readAsStringSync().trim());
        if (v != null && v >= tunerA4Min && v <= tunerA4Max) return v;
      }
    } catch (_) {}
    return tunerA4Default;
  }

  /// Tuner reference pitch (A4), 430..450 Hz in 1 Hz steps.
  void setTunerA4(double hz) {
    final v = hz.roundToDouble().clamp(tunerA4Min, tunerA4Max).toDouble();
    if (v == tunerA4) return;
    tunerA4 = v;
    tunerCents = null; // restart smoothing on the new reference
    final p = _tunerPath;
    if (p != null) {
      try {
        File(p).writeAsStringSync(v.toStringAsFixed(0));
      } catch (_) {}
    }
    _notify();
  }
  Future<void> closeTuner({bool sendOff = true}) async {
    if (!tunerOpen) return;
    tunerOpen = false;
    _tunerTimer?.cancel();
    _notify();
    if (sendOff && link.connected) {
      try {
        await link.tuner(false);
      } catch (_) {}
    }
  }

  bool get looperOn => live?.looperMode ?? false;

  Future<void> toggleLooper() => run(() async {
        _requireConnection();
        await link.looperMode(!looperOn);
        live = await link.readLive();
      });

  int get loopLevel => loopLevelOverride ?? live?.levelPercent ?? 100;

  void setLoopLevel(int percent) {
    loopLevelOverride = percent;
    _notify();
    _loopLevelTimer?.cancel();
    _loopLevelTimer = Timer(const Duration(milliseconds: 80), () async {
      try {
        if (link.connected) await link.loopLevel(percent);
      } catch (_) {}
    });
  }

  /// Looper STOP (2) / CLEAR (3) from the app.
  Future<void> loopAction(int action) => run(() async {
        _requireConnection();
        await link.looperAction(action);
        live = await link.readLive();
      });

  // ---------------------------------------------------------------- input trim
  int? _trimOverride;
  Timer? _trimTimer;

  /// Input trim of the current instrument (dB), null when unknown.
  int? get inputTrim {
    if (_trimOverride != null) return _trimOverride;
    final l = live;
    return l == null ? null : (bass ? l.trimBass : l.trimGuitar);
  }

  void setInputTrim(int db) {
    db = db < -24 ? -24 : (db > 24 ? 24 : db);
    _trimOverride = db;
    _notify();
    _trimTimer?.cancel();
    _trimTimer = Timer(const Duration(milliseconds: 150), () async {
      try {
        if (link.connected) {
          await link.inputTrim(db);
          live = await link.readLive();
        }
      } catch (e) {
        _report(e);
      }
      _trimOverride = null;
      _notify();
    });
  }

  /// Trim that brings the logged input level of this instrument to what the presets
  /// were voiced for (IN average -28 dBFS guitar / -26 dBFS bass). null = not enough log.
  TrimSuggestion? get trimSuggestion {
    final mode = library.data.mode;
    final recent = levelLog.entries.where((e) => e.mode == mode && e.duration.inSeconds >= 8).toList();
    if (recent.length > 12) recent.removeRange(0, recent.length - 12);
    final total = recent.fold<int>(0, (a, e) => a + e.duration.inMilliseconds);
    if (recent.isEmpty || total < 20000) return null;
    final avg = recent.fold<double>(0, (a, e) => a + e.inAvgDb * e.duration.inMilliseconds) / total;
    final maxIn = recent.map((e) => e.inMaxDb).reduce((a, b) => a > b ? a : b);
    var db = ((mode == 'bass' ? -26.0 : -28.0) - avg).round();
    final headroom = (-1 - maxIn).floor(); // keep the loudest hit below full scale
    if (db > headroom) db = headroom;
    db = db < -12 ? -12 : (db > 12 ? 12 : db);
    return TrimSuggestion(db, avg, recent.length);
  }

  void endLoopLevelDrag() {
    _loopLevelEndTimer?.cancel();
    _loopLevelEndTimer = Timer(const Duration(milliseconds: 900), () {
      loopLevelOverride = null;
      _notify();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _flushTimer?.cancel();
    _meterTimer?.cancel();
    _tunerTimer?.cancel();
    _loopLevelTimer?.cancel();
    _loopLevelEndTimer?.cancel();
    _trimTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _errors.close();
    link.dispose();
    meters.dispose();
    paramTick.dispose();
    super.dispose();
  }
}

class TrimSuggestion {
  const TrimSuggestion(this.db, this.avgDb, this.sessions);
  final int db;
  final double avgDb;
  final int sessions;
}
