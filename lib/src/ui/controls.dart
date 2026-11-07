// Instrument-style controls. Knob / fader: vertical drag (Shift = fine), mouse wheel,
// ↑↓ keys, double-click = back to the saved value. Values set from outside (RIG / tone loads) glide like motorised knobs.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
bool get _fine => HardwareKeyboard.instance.isShiftPressed;

/// Value after a vertical drag of [pixels] (up = positive).
double knobDragValue(double initial, double pixels, bool fine) => _c01(initial + pixels / (fine ? 960 : 240));

/// Shared drag / wheel / keyboard handling. [builder] gets the value to draw
/// (animated when the value changes from outside, immediate while dragging).
class _DragValue extends StatefulWidget {
  const _DragValue({required this.value, required this.onChanged, required this.pixelsPerRange, required this.tip, required this.builder, this.onReset});
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset; // double-click
  final double pixelsPerRange;
  final String tip;
  final Widget Function(BuildContext context, double shown, bool active) builder;

  @override
  State<_DragValue> createState() => _DragValueState();
}

class _DragValueState extends State<_DragValue> {
  double _v = 0;
  bool _drag = false;
  final _sinceOwn = Stopwatch(); // time since this control last produced a value itself
  Duration? _lastDown;
  Offset _lastDownAt = Offset.zero;

  // double-click detection without joining the gesture arena (drag stays immediate)
  void _pointerDown(PointerDownEvent e) {
    final prev = _lastDown;
    if (widget.onReset != null && prev != null && e.timeStamp - prev < const Duration(milliseconds: 320) && (e.position - _lastDownAt).distance < 8) {
      _lastDown = null;
      widget.onReset!();
      return;
    }
    _lastDown = e.timeStamp;
    _lastDownAt = e.position;
  }
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _set(double v) {
    _v = _c01(v);
    _sinceOwn
      ..reset()
      ..start();
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is KeyUpEvent) return KeyEventResult.ignored;
        final step = _fine ? .002 : .01;
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          _set(widget.value + step);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          _set(widget.value - step);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
              GestureBinding.instance.pointerSignalResolver.register(e, (_) {
                _set(widget.value - e.scrollDelta.dy.sign * (_fine ? .002 : .01));
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (_) => _focus.requestFocus(),
            onVerticalDragStart: (_) {
              _focus.requestFocus();
              _v = widget.value;
              setState(() => _drag = true);
            },
            onVerticalDragUpdate: (d) => _set(_v - d.delta.dy / (_fine ? widget.pixelsPerRange * 4 : widget.pixelsPerRange)),
            onVerticalDragEnd: (_) => setState(() => _drag = false),
            onVerticalDragCancel: () => setState(() => _drag = false),
            child: Tooltip(
              message: widget.tip,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: widget.value),
                // direct input follows the pointer 1:1; only external changes (tone load) glide
                duration: _drag || (_sinceOwn.isRunning && _sinceOwn.elapsedMilliseconds < 400) ? Duration.zero : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => widget.builder(context, v, _drag),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rotary knob with an LED collar.
class Knob extends StatelessWidget {
  Knob({super.key, required this.value, required this.onChanged, this.size = 100, Color? accent, this.onReset}) : accent = accent ?? Rx.red;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) => _DragValue(
        value: value,
        onChanged: onChanged,
        pixelsPerRange: 240,
        onReset: onReset,
        tip: onReset == null ? '上下ドラッグで回転 / Shift：微調整' : '上下ドラッグで回転 / Shift：微調整 / ダブルクリック：保存値に戻す',
        builder: (context, v, active) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _KnobPainter(v, accent, active)),
        ),
      );
}

class _KnobPainter extends CustomPainter {
  _KnobPainter(this.value, this.accent, this.active);
  final double value;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s, s);
    const c = Offset(50, 50);
    Offset polar(double deg, double r) => Offset(c.dx + r * math.cos(deg * math.pi / 180), c.dy + r * math.sin(deg * math.pi / 180));
    final style = Rx.t.knob;
    if (style != KnobStyle.studio) {
      _paintThemed(canvas, style, polar);
      canvas.restore();
      return;
    }

    // LED collar: 11 dots, lit up to the value
    for (var i = 0; i <= 10; i++) {
      final a = -225.0 + 27 * i;
      final lit = i / 10 <= value + 1e-6;
      final p = polar(a, 46);
      if (lit) canvas.drawCircle(p, 4.2, Paint()..color = accent.withValues(alpha: active ? .7 : .45)..maskFilter = Rx.blur(3));
      canvas.drawCircle(p, 2.1, Paint()..color = lit ? Color.lerp(accent, Colors.white, .25)! : Rx.ledOff);
    }
    // value arc
    if (value > .001) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 39.5),
        -225 * math.pi / 180,
        270 * value * math.pi / 180,
        false,
        Paint()
          ..color = accent.withValues(alpha: .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
    // drop shadow
    canvas.drawCircle(const Offset(50, 54), 35, Paint()..color = Colors.black.withValues(alpha: .7)..maskFilter = Rx.blur(5));
    // knurled skirt (rotates)
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((-135 + 270 * value) * math.pi / 180);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(c, 35, Paint()..color = const Color(0xFF111316));
    final knurl = Paint()
      ..color = const Color(0xFF3A3F47)
      ..strokeWidth = 1.6;
    for (var i = 0; i < 40; i++) {
      final a = i * 9.0;
      canvas.drawLine(polar(a, 31.5), polar(a, 35), knurl);
    }
    canvas.restore();
    // brushed aluminium cap with a fixed light sheen
    final cap = Rect.fromCircle(center: c, radius: 28);
    canvas.drawCircle(
      c,
      28,
      Paint()
        ..shader = const SweepGradient(colors: [
          Color(0xFF8C939C), Color(0xFF3E434B), Color(0xFFD9DDE2), Color(0xFF454A52), Color(0xFF9CA3AC), Color(0xFF3E434B), Color(0xFF8C939C),
        ]).createShader(cap),
    );
    canvas.drawCircle(c, 28, Paint()..style = PaintingStyle.stroke..color = Colors.black.withValues(alpha: .6)..strokeWidth = 1.2);
    canvas.drawCircle(c, 20, Paint()..shader = const RadialGradient(colors: [Color(0xFF2B2F35), Color(0xFF16181C)]).createShader(Rect.fromCircle(center: c, radius: 20)));
    // pointer
    final a = -225 + 270 * value;
    canvas.drawLine(polar(a, 7), polar(a, 26), Paint()..color = accent.withValues(alpha: .6)..strokeWidth = 6..strokeCap = StrokeCap.round..maskFilter = Rx.blur(3));
    canvas.drawLine(polar(a, 7), polar(a, 26), Paint()..color = Color.lerp(accent, Colors.white, .35)!..strokeWidth = 3..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  /// Console (grey skirt + coloured cap), Hi-Fi (knurled silver) and Board (black dome) knobs.
  void _paintThemed(Canvas canvas, KnobStyle style, Offset Function(double, double) polar) {
    const c = Offset(50, 50);
    final a = -225 + 270 * value;
    final rad = math.pi / 180;
    switch (style) {
      case KnobStyle.cap:
        final tick = Paint()
          ..color = Rx.onBlock.withValues(alpha: .75)
          ..strokeWidth = 1.6;
        for (var i = 0; i <= 10; i++) {
          final d = -225.0 + 27 * i;
          canvas.drawLine(polar(d, 42), polar(d, i % 5 == 0 ? 49 : 46), tick);
        }
        if (value > .001) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: 39), -225 * rad, 270 * value * rad, false,
              Paint()..color = accent.withValues(alpha: active ? .95 : .6)..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round);
        }
        canvas.drawCircle(const Offset(50, 54), 34, Paint()..color = Colors.black.withValues(alpha: .6)..maskFilter = Rx.blur(5));
        canvas.drawCircle(c, 34, Paint()..shader = const RadialGradient(center: Alignment(-.2, -.4), colors: [Color(0xFF4A5056), Color(0xFF15181B)]).createShader(Rect.fromCircle(center: c, radius: 34)));
        canvas.drawCircle(c, 34, Paint()..style = PaintingStyle.stroke..color = Colors.black..strokeWidth = 1);
        canvas.drawLine(polar(a, 18), polar(a, 32), Paint()..color = const Color(0xFFF4F1EA)..strokeWidth = 3.6..strokeCap = StrokeCap.round);
        canvas.drawCircle(
          c,
          15,
          Paint()
            ..shader = RadialGradient(center: const Alignment(-.3, -.4), colors: [Color.lerp(accent, Colors.white, .45)!, accent, Color.lerp(accent, Colors.black, .35)!])
                .createShader(Rect.fromCircle(center: c, radius: 15)),
        );
        if (active) canvas.drawCircle(c, 15, Paint()..color = accent.withValues(alpha: .5)..maskFilter = Rx.blur(4));
      case KnobStyle.silver:
        final tick = Paint()
          ..color = Rx.onBlock.withValues(alpha: .85)
          ..strokeWidth = 1.4;
        for (var i = 0; i <= 20; i++) {
          final d = -225.0 + 13.5 * i;
          canvas.drawLine(polar(d, 43), polar(d, i % 5 == 0 ? 50 : 46.5), tick);
        }
        canvas.drawCircle(const Offset(50, 53), 36, Paint()..color = Colors.black.withValues(alpha: .4)..maskFilter = Rx.blur(4));
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(a * rad);
        canvas.translate(-c.dx, -c.dy);
        canvas.drawCircle(c, 36, Paint()..color = const Color(0xFFA2A7AC));
        final knurl = Paint()..strokeWidth = 1.4;
        for (var i = 0; i < 60; i++) {
          final d = i * 6.0;
          knurl.color = i.isEven ? const Color(0xFFE8EAED) : const Color(0xFF80858A);
          canvas.drawLine(polar(d, 30), polar(d, 36), knurl);
        }
        canvas.restore();
        canvas.drawCircle(
          c,
          29,
          Paint()..shader = const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFF7F8F9), Color(0xFFB9BDC2), Color(0xFF8B9095)]).createShader(Rect.fromCircle(center: c, radius: 29)),
        );
        canvas.drawCircle(c, 29, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF7B8085)..strokeWidth = 1);
        canvas.drawLine(polar(a, 9), polar(a, 26), Paint()..color = accent..strokeWidth = 3.6..strokeCap = StrokeCap.butt);
        if (active) canvas.drawCircle(c, 40, Paint()..style = PaintingStyle.stroke..color = accent.withValues(alpha: .45)..strokeWidth = 2);
      case KnobStyle.dome:
        for (var i = 0; i <= 10; i++) {
          final lit = i / 10 <= value + 1e-6;
          final p = polar(-225.0 + 27 * i, 45);
          if (lit) canvas.drawCircle(p, 3.6, Paint()..color = accent.withValues(alpha: .4)..maskFilter = Rx.blur(2.5));
          canvas.drawCircle(p, 1.9, Paint()..color = lit ? Color.lerp(accent, Colors.white, .2)! : Rx.ledOff);
        }
        canvas.drawCircle(const Offset(50, 55), 33, Paint()..color = Colors.black.withValues(alpha: .7)..maskFilter = Rx.blur(6));
        canvas.drawCircle(c, 33, Paint()..shader = const RadialGradient(center: Alignment(-.35, -.45), colors: [Color(0xFF6A6A6A), Color(0xFF1A1A1A), Color(0xFF0A0A0A)], stops: [0, .7, 1]).createShader(Rect.fromCircle(center: c, radius: 33)));
        canvas.drawCircle(c, 33, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: .1)..strokeWidth = 1);
        canvas.drawLine(polar(a, 10), polar(a, 30), Paint()..color = const Color(0xFFF2F2F2)..strokeWidth = 3.4..strokeCap = StrokeCap.round);
        if (active) canvas.drawCircle(c, 36, Paint()..style = PaintingStyle.stroke..color = accent.withValues(alpha: .5)..strokeWidth = 2);
      case KnobStyle.studio:
        break;
    }
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value || old.accent != accent || old.active != active;
}

/// Long-throw fader with a lit rail.
class Fader extends StatelessWidget {
  Fader({super.key, required this.value, required this.onChanged, Color? accent, this.onReset}) : accent = accent ?? Rx.red;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final Color accent;

  @override
  Widget build(BuildContext context) => _DragValue(
        value: value,
        onChanged: onChanged,
        pixelsPerRange: 168,
        onReset: onReset,
        tip: onReset == null ? '上下ドラッグ / Shift：微調整' : '上下ドラッグ / Shift：微調整 / ダブルクリック：保存値に戻す',
        builder: (context, v, active) => SizedBox(width: 96, height: 218, child: CustomPaint(painter: _FaderPainter(v, accent, active))),
      );
}

class _FaderPainter extends CustomPainter {
  _FaderPainter(this.value, this.accent, this.active);
  final double value;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = Rx.onBlock.withValues(alpha: .28)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final y = 25 + i * 16.8;
      canvas.drawLine(Offset(16, y), Offset(i % 5 == 0 ? 30 : 25, y), tick);
      canvas.drawLine(Offset(70, y), Offset(i % 5 == 0 ? 84 : 77, y), tick);
    }
    final rail = RRect.fromRectAndRadius(const Rect.fromLTWH(44, 17, 10, 185), const Radius.circular(5));
    canvas.drawRRect(rail, Paint()..color = Colors.black);
    canvas.drawRRect(rail, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: .08));
    final cy = 193 - 168 * value;
    final lit = RRect.fromRectAndRadius(Rect.fromLTRB(47, cy, 51, 199), const Radius.circular(2));
    canvas.drawRRect(lit, Paint()..color = accent.withValues(alpha: .5)..maskFilter = Rx.blur(4));
    canvas.drawRRect(lit, Paint()..color = accent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(28, cy - 9, 42, 30), const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: .6)..maskFilter = Rx.blur(4));
    final capRect = Rect.fromLTWH(27, cy - 14, 44, 28);
    final cap = RRect.fromRectAndRadius(capRect, const Radius.circular(4));
    canvas.drawRRect(cap, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3F47), Color(0xFF16181C)]).createShader(capRect));
    canvas.drawRRect(cap, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: .15));
    for (var j = -8; j <= 8; j += 4) {
      if (j == 0) continue;
      canvas.drawLine(Offset(32, cy + j), Offset(66, cy + j), Paint()..color = Colors.black.withValues(alpha: .6)..strokeWidth = 1);
    }
    canvas.drawLine(Offset(30, cy), Offset(68, cy), Paint()..color = accent.withValues(alpha: .8)..strokeWidth = 5..maskFilter = Rx.blur(active ? 4 : 2));
    canvas.drawLine(Offset(30, cy), Offset(68, cy), Paint()..color = Color.lerp(accent, Colors.white, .4)!..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.value != value || old.accent != accent || old.active != active;
}

/// Rotary selector: a pointer knob plus lit position labels (tap a label or the knob).
class RotarySelector extends StatelessWidget {
  RotarySelector({super.key, required this.choices, required this.index, required this.onChanged, Color? accent}) : accent = accent ?? Rx.red;
  final List<String> choices;
  final int index;
  final ValueChanged<int> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final n = math.max(1, choices.length);
    return SizedBox(
      width: 110,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => onChanged((index + 1) % n),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: n <= 1 ? 0 : index / (n - 1)),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => SizedBox(width: 62, height: 62, child: CustomPaint(painter: _SelectorPainter(v, n, accent))),
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < choices.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: choices.length > 5 ? 1.5 : 3.5), // 7 types still fit the cell
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170), curve: Curves.easeOutCubic,
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 10, right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index ? accent : Rx.ledOff,
                    boxShadow: i == index ? [BoxShadow(color: accent.withValues(alpha: .8), blurRadius: 7)] : const [],
                  ),
                ),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 170), curve: Curves.easeOutCubic,
                    style: TextStyle(fontFamily: Rx.condensed, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: i == index ? Rx.onBlock : Rx.onBlock.withValues(alpha: .45)),
                    child: Text(choices[i], overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _SelectorPainter extends CustomPainter {
  _SelectorPainter(this.t, this.n, this.accent);
  final double t;
  final int n;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    double ang(double f) => (-135 + 270 * f) * math.pi / 180 - math.pi / 2;
    for (var i = 0; i < n; i++) {
      final a = ang(n <= 1 ? 0 : i / (n - 1));
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r - 5), c + Offset(math.cos(a), math.sin(a)) * r, Paint()..color = Rx.onBlock.withValues(alpha: .4)..strokeWidth = 1.5);
    }
    canvas.drawCircle(c + const Offset(0, 3), r - 8, Paint()..color = Colors.black54..maskFilter = Rx.blur(4));
    final body = Rect.fromCircle(center: c, radius: r - 8);
    canvas.drawCircle(c, r - 8, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3C414A), Color(0xFF15171B)]).createShader(body));
    canvas.drawCircle(c, r - 8, Paint()..style = PaintingStyle.stroke..color = Colors.black);
    final a = ang(t);
    final dir = Offset(math.cos(a), math.sin(a));
    // chicken-head pointer
    final tip = c + dir * (r - 10);
    final side = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((c + side * 7).dx, (c + side * 7).dy)
      ..lineTo((c - dir * 9).dx, (c - dir * 9).dy)
      ..lineTo((c - side * 7).dx, (c - side * 7).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE9E6E0));
    canvas.drawLine(c, tip, Paint()..color = accent..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_SelectorPainter old) => old.t != t || old.n != n || old.accent != accent;
}

/// Metal footswitch with a jewel LED (the effect's bypass).
class StompSwitch extends StatefulWidget {
  StompSwitch({super.key, required this.on, required this.onChanged, this.size = 58, Color? color}) : color = color ?? Rx.red;
  final bool on;
  final ValueChanged<bool> onChanged;
  final double size;
  final Color color;
  @override
  State<StompSwitch> createState() => _StompSwitchState();
}

class _StompSwitchState extends State<StompSwitch> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () => widget.onChanged(!widget.on),
        child: Tooltip(
          message: widget.on ? 'クリックでバイパス' : 'クリックでON',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            JewelLed(on: widget.on, color: widget.color, size: s * .26),
            SizedBox(height: s * .14),
            AnimatedScale(
              scale: _down ? .9 : 1,
              duration: const Duration(milliseconds: 150), curve: Curves.easeOutCubic,
              child: SizedBox(width: s, height: s, child: CustomPaint(painter: _StompPainter(_down))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _StompPainter extends CustomPainter {
  _StompPainter(this.down);
  final bool down;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c + const Offset(0, 3), r * .95, Paint()..color = Colors.black87..maskFilter = Rx.blur(5));
    canvas.drawCircle(c, r * .95, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFDADDE2), Color(0xFF50555D)]).createShader(Rect.fromCircle(center: c, radius: r)));
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * .82, r * .08, Paint()..color = Colors.black.withValues(alpha: .25));
    }
    final top = Rect.fromCircle(center: c, radius: r * .62);
    canvas.drawCircle(c, r * .62, Paint()..shader = RadialGradient(center: const Alignment(-.3, -.4), colors: down ? const [Color(0xFF9CA3AC), Color(0xFF3A3F46)] : const [Color(0xFFF2F4F6), Color(0xFF6D737B)]).createShader(top));
    canvas.drawCircle(c, r * .62, Paint()..style = PaintingStyle.stroke..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_StompPainter old) => old.down != down;
}

/// Jewel LED with an animated glow.
class JewelLed extends StatelessWidget {
  JewelLed({super.key, required this.on, Color? color, this.size = 12}) : color = color ?? Rx.red;
  final bool on;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 140), curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-.3, -.35),
            colors: on ? [Color.lerp(color, Colors.white, .6)!, color, Color.lerp(color, Colors.black, .35)!] : [const Color(0xFF4A3A3A), Color.lerp(color, Colors.black, .8)!, Colors.black],
          ),
          boxShadow: on ? [BoxShadow(color: color.withValues(alpha: .75), blurRadius: size * 1.1, spreadRadius: size * .1)] : const [],
          border: Border.all(color: Colors.black.withValues(alpha: .7)),
        ),
      );
}

/// Small LCD readout (value under a control, DSP load, ...).
class LcdReadout extends StatelessWidget {
  LcdReadout(this.text, {super.key, Color? color, this.width, this.active = false, this.fontSize = 12.5}) : color = color ?? Rx.lcd(false);
  final String text;
  final Color color;
  final double? width;
  final bool active;
  final double fontSize;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150), curve: Curves.easeOutCubic,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0xFF0C0A07), color, active ? .12 : .05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color.withValues(alpha: .7) : Colors.black),
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 10)] : const [],
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(fontFamily: Rx.mono, color: color, fontSize: fontSize + 1, letterSpacing: .3, shadows: Rx.glow(color, active ? 10 : 6)),
        ),
      );
}
