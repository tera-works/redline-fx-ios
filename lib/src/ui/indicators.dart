// Displays: footswitch side view, LED ladder meters, 7-segment digits, LCD glass,
// strobe tuner.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../level_log.dart';
import 'theme.dart';

/// Pedal footswitch seen from the side (pressed = ON tone sounding). null = unknown.
/// The plunger travels with a short spring animation.
class FootswitchView extends StatelessWidget {
  const FootswitchView({super.key, required this.pressed, this.scale = 1});
  final bool? pressed;
  final double scale;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '本体フットスイッチの状態（横から見た表示）',
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic,
          opacity: pressed == null ? .35 : 1,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: pressed == true ? 1 : 0),
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => SizedBox(width: 112 * scale, height: 76 * scale, child: CustomPaint(painter: _FootPainter(t))),
          ),
        ),
      );
}

class _FootPainter extends CustomPainter {
  _FootPainter(this.t);
  final double t; // 0 up .. 1 down

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 112;
    canvas.scale(s, s);
    Paint grad(Rect r, List<Color> c, {bool vertical = true}) => Paint()
      ..shader = LinearGradient(begin: vertical ? Alignment.topCenter : Alignment.centerLeft, end: vertical ? Alignment.bottomCenter : Alignment.centerRight, colors: c)
          .createShader(r);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black
      ..strokeWidth = 1.5;
    const chassis = Rect.fromLTWH(8, 49, 96, 22);
    canvas.drawRRect(RRect.fromRectAndRadius(chassis, const Radius.circular(4)), grad(chassis, const [Color(0xFF7A1A24), Color(0xFF2A0F13)]));
    canvas.drawRRect(RRect.fromRectAndRadius(chassis, const Radius.circular(4)), stroke);
    final led = t.clamp(0.0, 1.0).toDouble();
    if (led > .05) canvas.drawCircle(const Offset(87, 55), 7, Paint()..color = Rx.red.withValues(alpha: .55 * led)..maskFilter = Rx.blur(4));
    canvas.drawOval(Rect.fromCenter(center: const Offset(87, 55), width: 8, height: 4), Paint()..color = Color.lerp(const Color(0xFF5A0000), Rx.red, led)!);
    final dy = 12 * t;
    final shaft = Rect.fromLTWH(43, 23 + dy, 26, 27);
    canvas.drawRect(shaft, grad(shaft, const [Color(0xFFC0C0C0), Color(0xFF696969)], vertical: false));
    canvas.drawRect(shaft, stroke);
    final head = Rect.fromLTWH(30, 13 + 16 * t, 52, 13);
    canvas.drawRRect(RRect.fromRectAndRadius(head, const Radius.circular(3)), grad(head, const [Color(0xFFF5F5F5), Color(0xFF808080)]));
    canvas.drawRRect(RRect.fromRectAndRadius(head, const Radius.circular(3)), stroke);
    canvas.drawRect(const Rect.fromLTWH(36, 46, 40, 5), Paint()..color = const Color(0xFF696969));
    if (t > .02) {
      // the boot pressing the switch
      final boot = Rect.fromLTWH(14, 3 - 18 * (1 - t), 81, 24);
      final p = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF3F4248).withValues(alpha: t), const Color(0xFF14161A).withValues(alpha: t)]).createShader(boot);
      canvas.drawRRect(RRect.fromRectAndRadius(boot, const Radius.circular(6)), p);
      canvas.drawLine(Offset(18, boot.bottom - 4), Offset(90, boot.bottom - 4), Paint()..color = Colors.grey.withValues(alpha: t)..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_FootPainter old) => old.t != t;
}

/// Segmented LED ladder meter, -60..0 dBFS, peak hold segment and clip lamp.
/// Analog VU meter (console theme): cream face, needle with VU-like ballistics (~300 ms).
class VuMeter extends StatefulWidget {
  const VuMeter({super.key, required this.label, required this.meter, this.width = 150, this.height = 84});
  final String label;
  final MeterBallistics meter;
  final double width, height;

  @override
  State<VuMeter> createState() => _VuMeterState();
}

class _VuMeterState extends State<VuMeter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _v = ValueNotifier<double>(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      final target = ((widget.meter.level + 40) / 40).clamp(0.0, 1.0).toDouble();
      final v = _v.value;
      final next = v + (target - v) * math.min(1.0, dt * 6);
      if ((next - v).abs() > .002) {
        _v.value = next;
      } else {
        _ticker.stop(); // needle at rest: no frames until the level changes
      }
    })
      ..start();
  }

  @override
  void didUpdateWidget(VuMeter old) {
    super.didUpdateWidget(old);
    _wake();
  }

  void _wake() {
    final target = ((widget.meter.level + 40) / 40).clamp(0.0, 1.0).toDouble();
    if (!_ticker.isActive && (target - _v.value).abs() > .002) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: ValueListenableBuilder<double>(valueListenable: _v, builder: (context, v, _) => CustomPaint(painter: _VuPainter(widget.label, v))),
        ),
      );
}

class _VuPainter extends CustomPainter {
  _VuPainter(this.label, this.v);
  final String label;
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF15181B));
    final face = r.deflate(3);
    canvas.drawRRect(
      face,
      Paint()..shader = const RadialGradient(center: Alignment(0, 1.2), radius: 1.3, colors: [Color(0xFFFFF4D6), Color(0xFFF1DFAE), Color(0xFFD9C28A)]).createShader(face.outerRect),
    );
    canvas.save();
    canvas.clipRRect(face);
    final pivot = Offset(size.width / 2, size.height * 1.12);
    final len = size.height * .95;
    double ang(double f) => (-48 + 96 * f) * math.pi / 180 - math.pi / 2;
    final ink = Paint()
      ..color = const Color(0xFF3A2D18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCircle(center: pivot, radius: len * .82), ang(0), ang(.75) - ang(0), false, ink);
    canvas.drawArc(Rect.fromCircle(center: pivot, radius: len * .82), ang(.75), ang(1) - ang(.75), false, Paint()..color = const Color(0xFFC0281C)..strokeWidth = 3.5..style = PaintingStyle.stroke);
    for (var i = 0; i <= 10; i++) {
      final f = i / 10;
      final a = ang(f);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(pivot + d * len * .82, pivot + d * len * (i.isEven ? .92 : .88), Paint()..color = f > .75 ? const Color(0xFFC0281C) : const Color(0xFF3A2D18)..strokeWidth = 1.2);
    }
    final tp = TextPainter(
      text: TextSpan(text: 'VU  $label', style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Color(0xFF3A2D18))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height - tp.height - 6));
    final a = ang(v);
    canvas.drawLine(pivot, pivot + Offset(math.cos(a), math.sin(a)) * len, Paint()..color = const Color(0xFF151515)..strokeWidth = 1.6);
    canvas.restore();
    canvas.drawRRect(face, Paint()..style = PaintingStyle.stroke..color = Colors.black.withValues(alpha: .4)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_VuPainter old) => old.v != v || old.label != label;
}

/// The pedal reports peaks every 150 ms; the bar is animated per frame
/// (instant attack, smooth 26 dB/s fall) so it moves like a real LED meter.
class LedMeter extends StatefulWidget {
  const LedMeter({super.key, required this.label, required this.meter, this.width = 240, this.height = 16});
  final String label;
  final MeterBallistics meter;
  final double width, height;

  @override
  State<LedMeter> createState() => _LedMeterState();
}

class _LedMeterState extends State<LedMeter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _shown = ValueNotifier<double>(meterFloorDb);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.meter.level;
    final v = _shown.value;
    final next = target >= v ? target : (v - 60 * dt).clamp(target, 0.0).toDouble();
    if ((next - v).abs() > .01) {
      _shown.value = next;
    } else {
      // settled: stop asking for frames until the next level arrives (see didUpdateWidget)
      _shown.value = target;
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(LedMeter old) {
    super.didUpdateWidget(old);
    if (!_ticker.isActive && (widget.meter.level - _shown.value).abs() > .01) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ピーク（dBFS）。赤いランプ＝-1 dBFS超え（クリップ寸前）',
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height + 4,
          child: ValueListenableBuilder<double>(
            valueListenable: _shown,
            builder: (context, level, _) =>
                CustomPaint(painter: _LedMeterPainter(widget.label, level, widget.meter.hold, widget.meter.clipping(DateTime.now()))),
          ),
        ),
      ),
    );
  }
}

class _LedMeterPainter extends CustomPainter {
  _LedMeterPainter(this.label, this.level, this.hold, this.clip);
  final String label;
  final double level, hold;
  final bool clip;
  static const int segs = 28;
  static final Map<String, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    final tp = _labels.putIfAbsent(
        '${Rx.t.id.name}/$label',
        () => TextPainter(
              text: TextSpan(text: label, style: TextStyle(fontFamily: Rx.condensed, color: Rx.dim, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              textDirection: TextDirection.ltr,
            )..layout());
    tp.paint(canvas, Offset(0, (size.height - tp.height) / 2));
    const x0 = 32.0;
    final lampW = 14.0;
    final w = size.width - x0 - lampW - 6;
    final h = size.height - 6;
    final segW = w / segs;
    double dbAt(int i) => meterFloorDb + (i + 1) * (-meterFloorDb / segs);
    final holdSeg = hold <= meterFloorDb ? -1 : (((hold - meterFloorDb) / -meterFloorDb) * segs).floor().clamp(0, segs - 1);
    for (var i = 0; i < segs; i++) {
      final db = dbAt(i);
      final base = db > -6 ? Rx.red : (db > -18 ? Rx.amber : Rx.green);
      final lit = level >= db - (-meterFloorDb / segs) * .5;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x0 + i * segW + .8, 3, segW - 1.6, h), const Radius.circular(1.5));
      if (lit) canvas.drawRRect(r.inflate(1.2), Paint()..color = base.withValues(alpha: .35)..maskFilter = Rx.blur(2.5));
      canvas.drawRRect(r, Paint()..color = lit || i == holdSeg ? base : base.withValues(alpha: .12));
    }
    final lamp = Offset(size.width - lampW / 2, size.height / 2);
    if (clip) canvas.drawCircle(lamp, 8, Paint()..color = Rx.red.withValues(alpha: .7)..maskFilter = Rx.blur(4));
    canvas.drawCircle(lamp, 4.5, Paint()..color = clip ? const Color(0xFFFF2A2A) : const Color(0xFF3C1414));
  }

  @override
  bool shouldRepaint(_LedMeterPainter old) => old.level != level || old.hold != hold || old.clip != clip || old.label != label;
}

/// Seven-segment digits (unlit segments stay faintly visible, like real LED displays).
class SevenSeg extends StatelessWidget {
  const SevenSeg(this.text, {super.key, required this.color, this.height = 40});
  final String text;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: height * .62 * text.length, height: height, child: CustomPaint(painter: _SevenSegPainter(text, color)));
}

class _SevenSegPainter extends CustomPainter {
  _SevenSegPainter(this.text, this.color);
  final String text;
  final Color color;
  // segments a b c d e f g
  static const Map<String, int> _map = {
    '0': 0x3F, '1': 0x06, '2': 0x5B, '3': 0x4F, '4': 0x66, '5': 0x6D, '6': 0x7D, '7': 0x07, '8': 0x7F, '9': 0x6F, '-': 0x40, ' ': 0,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final dw = size.width / math.max(1, text.length);
    final h = size.height;
    final w = dw * .78;
    final t = h * .11;
    for (var k = 0; k < text.length; k++) {
      final bits = _map[text[k]] ?? 0;
      final ox = k * dw + (dw - w) / 2;
      // slanted like a real display
      canvas.save();
      canvas.translate(ox + h * .06, 0);
      canvas.transform((Matrix4.identity()..setEntry(0, 1, -.08)).storage);
      final segs = <Rect>[
        Rect.fromLTWH(t * .6, 0, w - t * 1.2, t), // a
        Rect.fromLTWH(w - t, t * .6, t, h / 2 - t * .9), // b
        Rect.fromLTWH(w - t, h / 2 + t * .3, t, h / 2 - t * .9), // c
        Rect.fromLTWH(t * .6, h - t, w - t * 1.2, t), // d
        Rect.fromLTWH(0, h / 2 + t * .3, t, h / 2 - t * .9), // e
        Rect.fromLTWH(0, t * .6, t, h / 2 - t * .9), // f
        Rect.fromLTWH(t * .6, h / 2 - t / 2, w - t * 1.2, t), // g
      ];
      for (var i = 0; i < 7; i++) {
        final on = (bits >> i) & 1 == 1;
        final r = RRect.fromRectAndRadius(segs[i], Radius.circular(t / 2));
        if (on) canvas.drawRRect(r, Paint()..color = color.withValues(alpha: .6)..maskFilter = Rx.blur(t * .7));
        canvas.drawRRect(r, Paint()..color = on ? Color.lerp(color, Colors.white, .15)! : color.withValues(alpha: .07));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SevenSegPainter old) => old.text != text || old.color != color;
}

/// LCD glass: dark tinted panel with scanlines and a reflection.
class LcdGlass extends StatelessWidget {
  const LcdGlass({super.key, required this.child, required this.color, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8)});
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Color.lerp(const Color(0xFF07080A), color, .06),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .10), blurRadius: 18),
            const BoxShadow(color: Color(0x22FFFFFF), offset: Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            foregroundPainter: const _GlassPainter(),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: .18);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: .07), Colors.transparent, Colors.transparent],
          stops: const [0, .45, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) => false;
}

/// Strobe tuner: rings drift left/right with the pitch error and freeze when in tune,
/// plus a needle.
class StrobePainter extends CustomPainter {
  StrobePainter({required this.phase, required this.cents, required this.color});
  final double phase; // radians, advanced by the caller
  final double? cents;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .92);
    final r = math.min(size.width / 2, size.height * .9) - 4;
    const bars = 40;
    final v = cents;
    final alpha = v == null ? .12 : (v.abs() < 2 ? .9 : .55);
    for (var ring = 0; ring < 3; ring++) {
      final rr = r - ring * r * .12;
      final ph = phase * (ring + 1);
      for (var i = 0; i < bars; i++) {
        final a = math.pi + (i / bars) * math.pi + ph % (math.pi / bars * 2);
        if (a > 2 * math.pi) continue;
        if (i.isOdd) continue;
        final p = Paint()
          ..color = color.withValues(alpha: alpha * (1 - ring * .25))
          ..strokeWidth = r * .07
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (rr - r * .05), c + Offset(math.cos(a), math.sin(a)) * rr, p);
      }
    }
    // scale
    for (var i = -50; i <= 50; i += 10) {
      final a = -math.pi / 2 + i * 1.4 * math.pi / 180;
      final len = i == 0 ? .16 : .09;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * .6, c + Offset(math.cos(a), math.sin(a)) * r * (.6 + len),
          Paint()..color = i == 0 ? Rx.green : Colors.white30..strokeWidth = i == 0 ? 3 : 1.5);
    }
    if (v != null) {
      final ok = v.abs() < 2;
      final a = -math.pi / 2 + v.clamp(-50.0, 50.0).toDouble() * 1.4 * math.pi / 180;
      final end = c + Offset(math.cos(a), math.sin(a)) * r * .78;
      canvas.drawLine(c, end, Paint()..color = (ok ? Rx.green : Rx.red).withValues(alpha: .4)..strokeWidth = 9..maskFilter = Rx.blur(5));
      canvas.drawLine(c, end, Paint()..color = ok ? Rx.green : Rx.red..strokeWidth = 3..strokeCap = StrokeCap.round);
    }
    canvas.drawCircle(c, 8, Paint()..color = const Color(0xFFC0C0C0));
    canvas.drawCircle(c, 8, Paint()..style = PaintingStyle.stroke..color = Colors.black);
  }

  @override
  bool shouldRepaint(StrobePainter old) => old.phase != phase || old.cents != cents || old.color != color;
}
