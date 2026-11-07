// Frame-time log: every 2 s one line with build (UI thread) and raster (GPU thread) times,
// written next to the app (perf-log.txt beside redline_fx.exe; falls back to the app's
// support folder).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'ui/theme.dart';

abstract final class PerfLog {
  static File? _file;
  static bool _described = false;
  static String path = '';
  static final List<double> _build = [], _raster = [];
  static DateTime _last = DateTime.now();

  static Future<void> start() async {
    try {
      final f = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}perf-log.txt');
      f.writeAsStringSync('');
      _file = f;
      path = f.path;
    } catch (_) {
      try {
        final f = File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}perf-log.txt');
        f.writeAsStringSync('');
        _file = f;
        path = f.path;
      } catch (_) {}
    }
    log('=== REDLINE FX ${DateTime.now().toIso8601String()} ===');
    log('os=${Platform.operatingSystemVersion} cpus=${Platform.numberOfProcessors} '
        'renderer=${_renderer()} theme=${Rx.t.id.name}');
    RxThemes.current.addListener(() => log('${_now()} theme -> ${Rx.t.id.name}'));
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static String _now() => DateTime.now().toIso8601String().substring(11, 23);

  // Impeller exposes shader image filters; Skia does not.
  static String _renderer() {
    try {
      return ui.ImageFilter.isShaderFilterSupported ? 'impeller' : 'skia';
    } catch (_) {
      return '?';
    }
  }

  /// Synchronous append: lines written in quick succession are never lost.
  static void log(String line) {
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!_described) {
      _described = true;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final v = views.first;
        log('window ${v.physicalSize.width.round()}x${v.physicalSize.height.round()} px, dpr ${v.devicePixelRatio}');
      }
    }
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    final now = DateTime.now();
    if (_raster.isEmpty || now.difference(_last) < const Duration(seconds: 2)) return;
    _last = now;
    double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
    double top(List<double> l) => l.reduce(math.max);
    final ra = avg(_raster);
    log('${_now()} theme=${Rx.t.id.name} frames=${_raster.length} '
        'build avg ${avg(_build).toStringAsFixed(1)} max ${top(_build).toStringAsFixed(1)} ms | '
        'raster avg ${ra.toStringAsFixed(1)} max ${top(_raster).toStringAsFixed(1)} ms');
    _build.clear();
    _raster.clear();
  }
}
