// BLE transport (universal_ble: Android / iOS / Windows). All plugin calls live here.
import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'models.dart';
import 'protocol.dart';

class NearbyDevice {
  const NearbyDevice(this.id, this.name, this.rssi);
  final String id;
  final String name;
  final int? rssi;
}

class BleException implements Exception {
  BleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Serialises GATT operations (one outstanding request at a time, like the .NET SemaphoreSlim).
class _Mutex {
  Future<void> _last = Future<void>.value();
  Future<T> run<T>(Future<T> Function() body) {
    final previous = _last;
    final done = Completer<void>();
    _last = done.future;
    return previous.then((_) => body()).whenComplete(() => done.complete());
  }
}

class PedalLink {
  PedalLink() {
    UniversalBle.onScanResult = _onScan;
    UniversalBle.onConnectionChange = (id, connected, error) {
      if (id == _deviceId && !connected) {
        _deviceId = null;
        _connectedController.add(false);
      }
    };
  }

  final _mutex = _Mutex();
  final _found = StreamController<NearbyDevice>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();
  String? _deviceId;
  bool _scanning = false;
  List<int> references = [0, 9];

  Stream<NearbyDevice> get found => _found.stream;

  /// Emits false when the pedal drops the connection.
  Stream<bool> get connectionChanges => _connectedController.stream;
  bool get connected => _deviceId != null;
  bool get scanning => _scanning;

  void _onScan(BleDevice d) {
    final name = d.name ?? '';
    final upper = name.toUpperCase();
    final hasService = d.services.any((s) => s.toLowerCase() == serviceUuid);
    if (hasService || upper.contains('REDLINE') || upper.contains('FX')) {
      _found.add(NearbyDevice(d.deviceId, name.isEmpty ? 'FX Pedal' : name, d.rssi));
    }
  }

  Future<void> startScan() async {
    if (_scanning) return;
    final state = await UniversalBle.getBluetoothAvailabilityState();
    if (state == AvailabilityState.poweredOff) throw BleException('Bluetooth がオフです');
    if (state == AvailabilityState.unsupported) throw BleException('この端末は Bluetooth LE に対応していません');
    try {
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
    } catch (e) {
      throw BleException('Bluetooth の使用が許可されていません');
    }
    await UniversalBle.startScan(
      platformConfig: PlatformConfig(android: AndroidOptions(requestLocationPermission: false, legacy: true)),
    );
    _scanning = true;
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  static final String _service = serviceUuid;

  Future<Uint8List> _read(int n) {
    final id = _deviceId;
    if (id == null) throw BleException('本体に接続してください');
    return UniversalBle.read(id, _service, charUuid(n), timeout: const Duration(seconds: 5));
  }

  Future<void> _write(int n, Uint8List value, {bool withoutResponse = false}) {
    final id = _deviceId;
    if (id == null) throw BleException('本体に接続してください');
    return UniversalBle.write(id, _service, charUuid(n), value, withoutResponse: withoutResponse, timeout: const Duration(seconds: 5));
  }

  Future<void> connect(String deviceId) => _mutex.run(() async {
        var stage = '端末を開く';
        try {
          await stopScan();
          await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 15));
          stage = 'サービスを取得する';
          final services = await UniversalBle.discoverServices(deviceId);
          BleService? fx;
          for (final s in services) {
            if (s.uuid.toLowerCase() == serviceUuid) fx = s;
          }
          if (fx == null) throw BleException('FXサービスが見つかりません');
          final have = fx.characteristics.map((c) => c.uuid.toLowerCase()).toSet();
          for (final n in Ch.needed) {
            if (!have.contains(charUuid(n))) throw BleException('本体ファームウェアが古いため接続できません。最新ファームウェアを書き込んでください');
          }
          try {
            await UniversalBle.requestMtu(deviceId, 517); // best effort (Android); others negotiate automatically
          } catch (_) {}
          _deviceId = deviceId;
          stage = '本体の音色形式を確認する';
          final probe = await _read(Ch.offSlot);
          if (probe.length != 1 + Tone.encodedLength || probe[1] != Tone.currentVersion) {
            throw BleException('本体ファームウェアが古いため接続できません。最新ファームウェアを書き込んでください');
          }
        } catch (e) {
          _deviceId = null;
          try {
            await UniversalBle.disconnect(deviceId);
          } catch (_) {}
          throw BleException('接続失敗（$stage）: $e');
        }
      });

  Future<void> disconnect() async {
    final id = _deviceId;
    _deviceId = null;
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
  }

  /// Status characteristic: DSP load plus level meters (peaks reset on every read).
  Future<(DeviceStatus, LevelStatus)> readStatus() => _mutex.run(() async {
        final s = await _read(Ch.status);
        return (DeviceStatus.parse(s), LevelStatus.parse(s));
      });

  Future<SwitchState> readSwitch() => _mutex.run(() async => SwitchState.parse(await _read(Ch.footswitch)));

  Future<LiveState> readLive() => _mutex.run(() async => LiveState.parse(await _read(Ch.live)));

  Future<void> _command(int cmd, int arg) => _mutex.run(() => _write(Ch.command, encodeCommand(cmd, arg)));

  Future<void> tuner(bool on) => _command(Cmd.tuner, on ? 1 : 0);
  Future<void> looperMode(bool on) => _command(Cmd.looperMode, on ? 1 : 0);
  Future<void> loopLevel(int percent) => _command(Cmd.loopLevel, percent < 0 ? 0 : (percent > 200 ? 200 : percent));
  Future<void> looperAction(int action) => _command(Cmd.looperAction, action);
  Future<void> bassMode(bool bass) => _command(Cmd.bassMode, bass ? 1 : 0);
  Future<void> inputTrim(int db) => _command(Cmd.inputTrim, (db < -24 ? -24 : (db > 24 ? 24 : db)) + 24);

  Future<List<Tone>> readPair() => _mutex.run(() async {
        final a = await _read(Ch.offSlot);
        final b = await _read(Ch.onSlot);
        references = [a[0], b[0]];
        return [Tone.decode(a.sublist(1)), Tone.decode(b.sublist(1))];
      });

  Future<void> _commit() async {
    await _write(Ch.command, encodeCommand(Cmd.commit, 0));
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = DeviceStatus.parse(await _read(Ch.status));
      if (!s.saveBusy) {
        if (s.saveError) throw BleException('本体への保存に失敗しました');
        return;
      }
    }
    throw BleException('保存完了を確認できません。本体から読み直してください');
  }

  /// Stage both slots and store them on the pedal.
  Future<void> assign(List<Tone> pair, List<int> refs) => _mutex.run(() async {
        try {
          for (var i = 0; i < 2; i++) {
            await _write(Ch.offSlot + i, Uint8List.fromList([refs[i], ...pair[i].encode()]));
          }
        } catch (_) {
          try {
            await _write(Ch.command, encodeCommand(Cmd.abort, 0));
          } catch (_) {}
          rethrow;
        }
        await _commit();
      });

  Future<void> param(int id, double norm) => _mutex.run(() => _write(Ch.param, encodeParam(id, norm), withoutResponse: true));

  void dispose() {
    UniversalBle.onScanResult = null;
    UniversalBle.onConnectionChange = null;
    stopScan();
    disconnect();
  }
}
