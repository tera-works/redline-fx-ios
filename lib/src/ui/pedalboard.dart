// The signal chain as a pedalboard: IN jack → mini pedals on a patch cable → OUT jack.
// Light pulses run along the cable, brighter with the input level (idle glow when
// disconnected). Tap a pedal = edit it, long press = on / off.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controller.dart';
import 'controls.dart';
import 'theme.dart';

class Pedalboard extends StatefulWidget {
  const Pedalboard({super.key, required this.c, this.pedalW = 88, this.height = 96});
  final PedalController c;
  final double pedalW, height;

  @override
  State<Pedalboard> createState() => _PedalboardState();
}

class _PedalboardState extends State<Pedalboard> with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  final _scroll = ScrollController();
  static const double _jackW = 46;

  /// Room between pedals (a real board leaves space for the side-jack patch cables).
  double get _gap => Rx.t.pedal == PedalStyle.stomp ? 30 : 14;
  double _k = .16; // smoothed signal strength (updated every frame)
  int? _shownBlock; // keeps the selected pedal in view whatever selected it

  @override
  void initState() {
    super.initState();
    _flow.addListener(() => _k += (_target() - _k) * .06);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void dispose() {
    _flow.dispose();
    _intro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  double _x(int i) => _jackW + _gap + i * (widget.pedalW + _gap);

  /// Stompboxes stand tall on a real board; the other styles use a compact 72 px body.
  double get _pedalH => Rx.t.pedal == PedalStyle.stomp ? widget.height - 30 : 72;

  void _reveal({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final i = widget.c.defaults.order.indexOf(widget.c.selectedBlock);
    final view = _scroll.position.viewportDimension;
    final target = (_x(i) + widget.pedalW / 2 - view / 2).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if (jump) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
  }

  void _page(int dir) {
    if (!_scroll.hasClients) return;
    final t = (_scroll.offset + dir * _scroll.position.viewportDimension * .7).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    _scroll.animateTo(t, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  /// 0..1 signal strength for the cable animation (raw, 150 ms steps).
  double _target() {
    final c = widget.c;
    if (!c.connected) return .16;
    final db = c.meters.input.level;
    return (.18 + (db + 60) / 50).clamp(.18, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final order = c.defaults.order;
    final total = _x(order.length) + _jackW;
    final enabled = [for (final b in order) c.blockEnabled(b)];
    if (_shownBlock != null && _shownBlock != c.selectedBlock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal();
      });
    }
    _shownBlock = c.selectedBlock;
    final flowing = c.connected && Rx.t.pedal != PedalStyle.stomp;
    if (flowing && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!flowing && _flow.isAnimating) {
      _flow.stop();
    }
    return RepaintBoundary(
      child: SizedBox(
      height: widget.height,
      child: Row(children: [
        _arrow(Icons.chevron_left, () => _page(-1)),
        Expanded(
          child: Stack(children: [
            if (Rx.t.pedal == PedalStyle.stomp) const Positioned.fill(child: CachedPaint(painter: _CarpetPainter(), cacheKey: 'carpet')),
            Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: total,
                height: widget.height,
                child: Stack(children: [
                  // the cable repaints every frame on its own layer; pedals stay cached
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _CablePainter(
                          repaint: _flow,
                          flow: _flow,
                          intensity: () => _k,
                          lefts: [for (var i = 0; i < order.length; i++) _x(i)],
                          pedalW: widget.pedalW,
                          pedalH: _pedalH,
                          jackW: _jackW,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(left: 0, top: 0, bottom: 0, width: _jackW, child: _Jack(label: 'IN')),
                  const Positioned(right: 0, top: 0, bottom: 0, width: _jackW, child: _Jack(label: 'OUT')),
                  for (var i = 0; i < order.length; i++)
                    Positioned(
                      left: _x(i),
                      top: 0,
                      bottom: 0,
                      width: widget.pedalW,
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, child) {
                          final t = ((_intro.value * (order.length + 6) - i) / 6).clamp(0.0, 1.0).toDouble();
                          final e = Curves.easeOutBack.transform(t);
                          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - e)), child: child));
                        },
                        child: RepaintBoundary(child: _MiniPedal(
                          c: c,
                          height: _pedalH,
                          index: i,
                          block: order[i],
                          name: c.defaults.blocks[order[i]],
                          on: enabled[i],
                          selected: order[i] == c.selectedBlock,
                          onTap: () {
                            c.selectBlock(order[i]);
                          },
                          onLongPress: () => c.toggleBlock(order[i]),
                        )),
                      ),
                    ),
                ]),
              ),
            ),
            ),
            // soft fade at both ends (cheap overlay instead of a shader mask)
            const Positioned(left: 0, top: 0, bottom: 0, width: 18, child: IgnorePointer(child: _EdgeFade(left: true))),
            const Positioned(right: 0, top: 0, bottom: 0, width: 18, child: IgnorePointer(child: _EdgeFade(left: false))),
          ]),
        ),
        _arrow(Icons.chevron_right, () => _page(1)),
      ]),
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) => SizedBox(
        width: 34,
        child: IconButton(onPressed: onTap, icon: Icon(icon), color: _frameInk, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
      );
}

Color get _surface => Rx.t.frame != null ? Rx.t.boardSurface : Rx.panel;

/// Labels drawn on the board surface (dark bed / carpet on Hi-Fi and Board).
Color get _boardInk => Rx.t.frame != null ? const Color(0xFFB9BDC2) : Rx.dim;

/// Scroll arrows sit on the frame (black on Hi-Fi, aluminium on Board).
Color get _frameInk => switch (Rx.t.pedal) {
      PedalStyle.key => const Color(0xFFB9BDC2),
      PedalStyle.stomp => const Color(0xFF2A2622),
      _ => Rx.dim,
    };

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.left});
  final bool left;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [_surface, _surface.withValues(alpha: 0)],
          ),
        ),
      );
}

class _CablePainter extends CustomPainter {
  _CablePainter({required Listenable repaint, required this.flow, required this.intensity, required this.lefts, required this.pedalW, required this.pedalH, required this.jackW}) : super(repaint: repaint);
  final Animation<double> flow;
  final double Function() intensity;
  final List<double> lefts; // pedal x positions
  final double pedalW, pedalH, jackW;

  /// REAL BOARD: input/output jacks on the sides of every stompbox, short patch cables
  /// with right-angle plugs in the gaps, and long cables to the guitar and the amp.
  void _paintPatchCables(Canvas canvas, Size size) {
    final top = (size.height - pedalH) / 2;
    final jy = top + pedalH * .3; // jack height on the enclosure side
    final black = Paint()
      ..color = const Color(0xFF050505)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;
    final cable = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final shine = Paint()
      ..color = Colors.white.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final nut = Paint()..color = const Color(0xFF9EA3A8);
    final nutDark = Paint()..color = const Color(0xFF3A3D41);
    final plugPaint = Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4F6F8), Color(0xFFA7ACB2), Color(0xFF6B7076)]).createShader(Rect.fromLTWH(0, jy - 7, 10, 14));
    final boot = Paint()..color = const Color(0xFF111111);

    // jack nut on the enclosure side + right-angle plug pointing down into the cable
    Offset plug(double x, bool rightSide) {
      final dir = rightSide ? 1.0 : -1.0;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + dir * 2, jy), width: 4, height: 12), const Radius.circular(1)), nut);
      canvas.drawRect(Rect.fromCenter(center: Offset(x + dir * 2, jy), width: 1.2, height: 12), nutDark);
      final px = x + dir * 8;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(px, jy), width: 9, height: 12), const Radius.circular(2)), plugPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px - 4, jy + 5, 8, 7), const Radius.circular(2)), boot);
      return Offset(px, jy + 11);
    }

    void run(Offset a, Offset b, double sag) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy + sag, b.dx, b.dy + sag, b.dx, b.dy);
      canvas.drawPath(path.shift(const Offset(1, 3)), Paint()..color = Colors.black.withValues(alpha: .5)..style = PaintingStyle.stroke..strokeWidth = 7);
      canvas.drawPath(path, black);
      canvas.drawPath(path, cable);
      canvas.drawPath(path.shift(const Offset(-.8, -.8)), shine);
    }

    if (lefts.isEmpty) return;
    // guitar -> first pedal
    final inJack = Offset(jackW / 2, size.height / 2 - 4);
    run(inJack, plug(lefts.first, false), pedalH * .45);
    for (var i = 0; i + 1 < lefts.length; i++) {
      final a = plug(lefts[i] + pedalW, true);
      final b = plug(lefts[i + 1], false);
      run(a, b, 16 + (i % 3) * 5);
    }
    // last pedal -> amp
    run(plug(lefts.last + pedalW, true), Offset(size.width - jackW / 2, size.height / 2 - 4), pedalH * .45);
  }

  static final Paint _shadow = Paint()
    ..color = Colors.black.withValues(alpha: .5)
    ..strokeWidth = 9
    ..strokeCap = StrokeCap.round;
  static final Paint _rubber = Paint()
    ..color = const Color(0xFF08090B)
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round;
  static final Paint _shine = Paint()
    ..color = Colors.white.withValues(alpha: .08)
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (Rx.t.pedal == PedalStyle.stomp) {
      _paintPatchCables(canvas, size);
      return;
    }
    final y = size.height * .56;
    final w = size.width;
    final k = intensity();
    canvas.drawLine(Offset(20, y + 2), Offset(w - 20, y + 2), _shadow);
    canvas.drawLine(Offset(20, y), Offset(w - 20, y), _rubber);
    canvas.drawLine(Offset(20, y - 1.5), Offset(w - 20, y - 1.5), _shine);
    canvas.drawLine(Offset(20, y), Offset(w - 20, y), Paint()..color = Rx.red.withValues(alpha: .10 + .22 * k)..strokeWidth = 2);
    // travelling pulses: radial-gradient glow (no blur filters, cheap at 60 fps)
    const n = 7;
    final core = Color.lerp(Rx.red, Rx.amber, .5)!;
    for (var i = 0; i < n; i++) {
      final f = (flow.value + i / n) % 1.0;
      final x = 20 + f * (w - 40);
      final wave = .6 + .4 * math.sin((f * 6 + i) * math.pi);
      final a = (k * wave).clamp(0.0, 1.0).toDouble();
      final c = Offset(x, y);
      canvas.drawCircle(
        c,
        12,
        Paint()..shader = RadialGradient(colors: [Rx.red.withValues(alpha: .45 * a), Rx.red.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 12)),
      );
      canvas.drawCircle(c, 2.2, Paint()..color = core.withValues(alpha: .95 * a));
    }
  }

  @override
  bool shouldRepaint(_CablePainter old) => false; // driven by [repaint]
}

/// Small black dome knob with a white line (stompbox on the board).
class _MiniKnobPainter extends CustomPainter {
  _MiniKnobPainter(this.value);
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c + const Offset(0, 1.5), r, Paint()..color = Colors.black54);
    canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(center: Alignment(-.35, -.45), colors: [Color(0xFF6A6A6A), Color(0xFF151515)]).createShader(Rect.fromCircle(center: c, radius: r)));
    final a = (-225 + 270 * value) * math.pi / 180;
    canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * .25, c + Offset(math.cos(a), math.sin(a)) * r * .85, Paint()..color = const Color(0xFFF2F2F2)..strokeWidth = 1.8..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_MiniKnobPainter old) => old.value != value;
}

/// Hook-and-loop carpet of a real pedalboard.
class _CarpetPainter extends CustomPainter {
  const _CarpetPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(r, Paint()..color = Rx.t.boardSurface);
    // loop pile: one dot every 4 px, drawn as two point batches (not one circle per dot)
    final rnd = math.Random(11);
    final light = <Offset>[], dark = <Offset>[];
    for (double y = 2; y < size.height; y += 4) {
      for (double x = 2 + (y % 8 == 2 ? 2 : 0); x < size.width; x += 4) {
        (rnd.nextBool() ? light : dark).add(Offset(x + rnd.nextDouble(), y + rnd.nextDouble()));
      }
    }
    Paint dots(Color c) => Paint()
      ..color = c
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, light, dots(Colors.white.withValues(alpha: .05)));
    canvas.drawPoints(ui.PointMode.points, dark, dots(Colors.black.withValues(alpha: .45)));
    canvas.drawRRect(r.deflate(.5), Paint()..style = PaintingStyle.stroke..color = Colors.black.withValues(alpha: .8)..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_CarpetPainter old) => false;
}

class _Jack extends StatelessWidget {
  const _Jack({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 14),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFF050506), Color(0xFF050506), Color(0xFFB9BEC5), Color(0xFF5B6068)], stops: [0, .42, .5, 1]),
            border: Border.all(color: Colors.black),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontFamily: Rx.condensed, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: _boardInk)),
      ]);
}

class _MiniPedal extends StatefulWidget {
  const _MiniPedal({required this.c, required this.height, required this.index, required this.block, required this.name, required this.on, required this.selected, required this.onTap, required this.onLongPress});
  final PedalController c;
  final double height;
  final int index, block;
  final String name;
  final bool on, selected;
  final VoidCallback onTap, onLongPress;
  @override
  State<_MiniPedal> createState() => _MiniPedalState();
}

class _MiniPedalState extends State<_MiniPedal> {
  bool _down = false;
  bool _hover = false;

  /// Status lamp: jewel (enclosures), lit square button (console), slim bar (hi-fi).
  Widget _led(PedalStyle style) {
    final on = widget.on;
    return switch (style) {
      PedalStyle.module => Container(
          width: 15,
          height: 9,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1.5),
            color: on ? Rx.red : Rx.ledOff,
            border: Border.all(color: Colors.black),
            boxShadow: on ? [BoxShadow(color: Rx.red.withValues(alpha: .7), blurRadius: 6)] : const [],
          ),
        ),
      PedalStyle.key => Container(
          width: 12,
          height: 5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: on ? Rx.red : Rx.ledOff,
            boxShadow: on ? [BoxShadow(color: Rx.red.withValues(alpha: .7), blurRadius: 5)] : const [],
          ),
        ),
      PedalStyle.anodized || PedalStyle.stomp => JewelLed(on: on, size: 8),
    };
  }

  /// REAL BOARD stompbox: three knobs showing the pedal's first settings, LED, name, footswitch.
  Widget _stompBody() {
    final c = widget.c;
    final enable = c.defaults.enableOf(widget.block);
    final knobs = c.defaults.paramsOf(widget.block).where((p) => p.id != enable?.id && !p.isBool && !p.isEnum).take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Column(children: [
        ListenableBuilder(
          listenable: c.paramTick,
          builder: (context, _) => Row(
            mainAxisAlignment: knobs.length > 1 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
            children: [for (final p in knobs) SizedBox(width: 19, height: 19, child: CustomPaint(painter: _MiniKnobPainter(c.value(p.id))))],
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: SizedBox()),
          JewelLed(on: widget.on, size: 9),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ListenableBuilder(
                listenable: c.paramTick,
                builder: (context, _) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                  opacity: c.blockEdited(widget.block) ? 1 : 0,
                  child: Transform.rotate(
                    angle: .14,
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: const BoxDecoration(color: Color(0xEEF0E4BE), boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))]),
                      child: const Text('EDIT', style: TextStyle(fontFamily: Rx.marker, fontSize: 9, height: 1.25, color: Color(0xFFC0281C))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(widget.name.toUpperCase(),
              style: TextStyle(fontFamily: Rx.display, fontSize: 15 * Rx.displayScale, fontWeight: FontWeight.w800, letterSpacing: 1, color: Rx.onBlock, shadows: const [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 1)])),
        ),
        Text('REDLINE FX', style: TextStyle(fontFamily: Rx.condensed, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Rx.onBlock.withValues(alpha: .45))),
        // footswitch in the lower part of the enclosure, not glued to the edge
        const Spacer(flex: 3),
        _foot(30),
        const Spacer(flex: 2),
      ]),
    );
  }

  /// Metal footswitch at the bottom of an enclosure.
  Widget _foot(double size) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .22),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFEDEFF2), Color(0xFF8A8E94), Color(0xFF50545A)]),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1.5))],
        ),
        child: size > 18
            ? Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .85), border: Border.all(color: Colors.black26)))
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final style = Rx.t.pedal;
    final key = style == PedalStyle.key;
    final base = Rx.block(widget.block);
    // a real stompbox keeps its colour when bypassed (only the LED goes out)
    final body = widget.on || style == PedalStyle.stomp ? base : Color.lerp(base, Rx.t.pedalOff, key ? .45 : .72)!;
    // a Hi-Fi key stays pressed down when selected; enclosures lift up
    final lift = widget.selected ? (key ? 2.0 : -5.0) : (_hover ? (key ? 0.0 : -2.0) : 0.0);
    final radius = switch (style) {
      PedalStyle.anodized => 9.0,
      PedalStyle.stomp => 7.0,
      _ => 3.0,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Tooltip(
          message: 'タップで編集 / 長押しで ON・OFF',
          waitDuration: const Duration(seconds: 1),
          child: Center(
            child: AnimatedScale(
              scale: _down ? .93 : 1,
              duration: const Duration(milliseconds: 170), curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, lift, 0),
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: style == PedalStyle.stomp ? Alignment.topLeft : Alignment.topCenter,
                    end: style == PedalStyle.stomp ? Alignment.bottomRight : Alignment.bottomCenter,
                    colors: [Color.lerp(body, Colors.white, key ? .5 : .14)!, body, Color.lerp(body, Colors.black, key ? .15 : .35)!],
                    stops: const [0, .4, 1],
                  ),
                  border: Border.all(color: widget.selected ? Rx.gold : (Rx.light ? Rx.line : Colors.black.withValues(alpha: .8)), width: widget.selected ? 2.5 : 1),
                  boxShadow: Rx.shadows([
                    BoxShadow(color: Colors.black.withValues(alpha: Rx.light ? .3 : .7), blurRadius: widget.selected && !key ? 14 : 6, offset: Offset(0, widget.selected && !key ? 8 : 3)),
                    if (widget.selected) BoxShadow(color: Rx.gold.withValues(alpha: .25), blurRadius: 16),
                    if (widget.on) BoxShadow(color: Rx.red.withValues(alpha: .22), blurRadius: 16, spreadRadius: 1),
                  ]),
                ),
                child: style == PedalStyle.stomp
                    ? _stompBody()
                    : Padding(
                  padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
                  child: Column(children: [
                    Row(children: [
                      _led(style),
                      const SizedBox(width: 4),
                      // knobs turned on this pedal (not saved yet); follows knob drags via paramTick
                      ListenableBuilder(
                        listenable: widget.c.paramTick,
                        builder: (context, _) {
                          final edited = widget.c.blockEdited(widget.block);
                          return Tooltip(
                            message: edited ? '変更あり（未保存）' : '',
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                              opacity: edited ? 1 : 0,
                              child: style == PedalStyle.stomp
                                  // masking tape with a marker note
                                  ? Transform.rotate(
                                      angle: .14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: const BoxDecoration(color: Color(0xEEF0E4BE), boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))]),
                                        child: const Text('EDIT', style: TextStyle(fontFamily: Rx.marker, fontSize: 9, height: 1.25, color: Color(0xFFC0281C))),
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Rx.gold,
                                        borderRadius: BorderRadius.circular(3),
                                        boxShadow: [BoxShadow(color: Rx.gold.withValues(alpha: .6), blurRadius: 5)],
                                      ),
                                      child: Text('EDIT', style: TextStyle(fontFamily: Rx.condensed, fontSize: 7.5, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: .6, color: Rx.light ? Colors.white : Colors.black)),
                                    ),
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      Text('${widget.index + 1}'.padLeft(2, '0'),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Rx.onBlock.withValues(alpha: .55), fontFeatures: Rx.tabular)),
                    ]),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(widget.name.toUpperCase(),
                          style: TextStyle(fontFamily: Rx.condensed, fontSize: 13, fontWeight: FontWeight.w800, fontStyle: style == PedalStyle.stomp ? Rx.italic : FontStyle.normal, letterSpacing: .8, color: widget.on ? Rx.onBlock : Rx.onBlock.withValues(alpha: .6))),
                    ),
                    SizedBox(height: style == PedalStyle.anodized || style == PedalStyle.stomp ? 4 : 8),
                    if (style == PedalStyle.anodized || style == PedalStyle.stomp) _foot(style == PedalStyle.stomp ? 22 : 16),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
