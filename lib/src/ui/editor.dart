// Editing: the selected effect as a pedal faceplate, OFF/ON scene cards, SAVE RIG,
// RIG / TONE libraries.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import 'controls.dart';
import 'theme.dart';

// ---------------------------------------------------------------- faceplate
const double _cellW = 110, _cellPad = 6, _cellH = 20 + 218 + 30, _headerH = 78, _platePad = 14;

/// Natural size of a faceplate with [count] controls in [columns] columns.
Size effectPanelSize(int count, int columns) {
  final rows = math.max(1, (count / columns).ceil());
  // margins 24 + padding 28 + control well 18 (+ slack)
  return Size(columns * (_cellW + 2 * _cellPad) + 76, _headerH + 84 + rows * (_cellH + 2 * _cellPad) + (Rx.t.pedal == PedalStyle.stomp ? 112 : 0));
}

/// Column count that shows the faceplate biggest in [box].
int bestColumns(int count, Size box) {
  if (count <= 0) return 1;
  var best = count, bestScale = 0.0;
  for (var cols = 1; cols <= count; cols++) {
    final s = effectPanelSize(count, cols);
    final scale = math.min(box.width / s.width, box.height / s.height);
    if (scale > bestScale + 1e-3) {
      bestScale = scale;
      best = cols;
    }
  }
  return best;
}

/// The selected effect, scaled to the area (never scrolls). Switching effects slides the
/// new faceplate in; loading a tone makes every knob glide to its new position.
class EffectFaceplate extends StatelessWidget {
  const EffectFaceplate({super.key, required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final block = c.selectedBlock;
    final enable = c.defaults.enableOf(block);
    final params = c.defaults.paramsOf(block).where((p) => p.id != enable?.id).toList();
    return LayoutBuilder(builder: (context, box) {
      final cols = bestColumns(params.length, box.biggest);
      final natural = effectPanelSize(params.length, cols);
      final scale = math.min(1.45, math.min(box.maxWidth / natural.width, box.maxHeight / natural.height));
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 290),
        switchInCurve: Curves.easeOutCubic,
        // only the incoming plate is drawn: no overlapping cross-fade (that read as ghosting)
        layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
        transitionBuilder: (child, anim) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(.035, 0), end: Offset.zero).animate(anim),
          child: child,
        ),
        child: Align(
          key: ValueKey(block),
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: natural.width * scale,
            height: natural.height * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: RepaintBoundary(child: SizedBox(width: natural.width, height: natural.height, child: _Faceplate(c: c, block: block, enable: enable, params: params))),
            ),
          ),
        ),
      );
    });
  }
}

class _Faceplate extends StatelessWidget {
  const _Faceplate({required this.c, required this.block, required this.enable, required this.params});
  final PedalController c;
  final int block;
  final Parameter? enable;
  final List<Parameter> params;

  @override
  Widget build(BuildContext context) {
    final position = c.defaults.order.indexOf(block);
    final on = c.blockEnabled(block);
    final color = Rx.block(block);
    final knobAccent = on ? Rx.red : Rx.dim;
    // REAL BOARD: the faceplate is a close-up of a powder-coated stompbox
    final stomp = Rx.t.pedal == PedalStyle.stomp;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(stomp ? 26 : 18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, Rx.light ? .45 : .12)!, color, Color.lerp(color, Colors.black, Rx.light ? .12 : .45)!],
          stops: const [0, .45, 1],
        ),
        border: Border.all(color: Rx.light ? Rx.line : Colors.black, width: 1.5),
        boxShadow: Rx.shadows([
          const BoxShadow(color: Color(0xCC000000), blurRadius: 26, offset: Offset(0, 12)),
          BoxShadow(color: (on ? Rx.red : Colors.transparent).withValues(alpha: .18), blurRadius: 40),
        ]),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        // bevel highlight
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(stomp ? 24 : 16),
                border: Border.all(color: Colors.white.withValues(alpha: stomp ? .2 : .12)),
              ),
            ),
          ),
        ),
        if (!stomp) const Positioned.fill(child: IgnorePointer(child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(16)), child: BrushedTexture()))),
        if (!stomp)
          for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
            Positioned.fill(child: Align(alignment: a, child: const Padding(padding: EdgeInsets.all(9), child: Screw(size: 11)))),
        if (stomp) ...[
          // input (right) / output (left) jacks on the sides, as on a real stompbox
          for (final left in [true, false])
            Positioned(
              top: 64,
              left: left ? -13 : null,
              right: left ? null : -13,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!left) Container(width: 5, height: 30, color: const Color(0xFF9EA3A8)),
                Container(
                  width: 11,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(colors: [Color(0xFF7C8187), Color(0xFFF2F4F6), Color(0xFF6E7379)]),
                    border: Border.all(color: Colors.black),
                  ),
                ),
                if (left) Container(width: 5, height: 30, color: const Color(0xFF9EA3A8)),
              ]),
            ),
          // masking tape when a knob was turned
          Positioned(
            top: 22,
            right: 96,
            child: ListenableBuilder(
              listenable: c.paramTick,
              builder: (context, _) => AnimatedOpacity(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                opacity: c.blockEdited(block) ? 1 : 0,
                child: Transform.rotate(
                  angle: .12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                    decoration: const BoxDecoration(color: Color(0xEEF0E4BE), boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))]),
                    child: const Text('EDIT', style: TextStyle(fontFamily: Rx.marker, fontSize: 18, color: Color(0xFFC0281C))),
                  ),
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(_platePad),
          child: Column(children: [
            SizedBox(
              height: _headerH,
              child: Row(children: [
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(c.defaults.blocks[block].toUpperCase(),
                        style: TextStyle(fontFamily: Rx.display,
                          fontSize: 40 * Rx.displayScale,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          fontStyle: Rx.italic,
                          letterSpacing: 3,
                          color: Rx.onBlock.withValues(alpha: .92),
                          shadows: Rx.light ? null : const [Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 3)],
                        )),
                    const SizedBox(height: 4),
                    Text('REDLINE FX  ·  ${(position + 1).toString().padLeft(2, '0')} / ${c.defaults.order.length.toString().padLeft(2, '0')}',
                        style: TextStyle(fontFamily: Rx.condensed, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2.5, color: Rx.onBlock.withValues(alpha: .5))),
                  ]),
                ),
                if (enable != null && !stomp) StompSwitch(on: on, size: 46, onChanged: (v) => c.setParam(enable!, v ? 1 : 0)),
                const SizedBox(width: 18),
              ]),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                opacity: on ? 1 : .72,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: stomp ? Colors.transparent : Rx.well,
                    border: stomp ? null : Border.all(color: Colors.black.withValues(alpha: Rx.light ? .18 : .6)),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in params)
                        // knob edits only tick c.paramTick: just these cells rebuild while dragging
                        ListenableBuilder(listenable: c.paramTick, builder: (context, _) => _ParamCell(c: c, p: p, accent: knobAccent, lcd: Rx.lcd(c.bass))),
                    ],
                  ),
                ),
              ),
            ),
            // a real stompbox has its footswitch (with the LED above it) at the bottom
            if (stomp && enable != null) ...[
              const SizedBox(height: 10),
              StompSwitch(on: on, size: 66, onChanged: (v) => c.setParam(enable!, v ? 1 : 0)),
              const SizedBox(height: 6),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _ParamCell extends StatefulWidget {
  const _ParamCell({required this.c, required this.p, required this.accent, required this.lcd});
  final PedalController c;
  final Parameter p;
  final Color accent, lcd;
  @override
  State<_ParamCell> createState() => _ParamCellState();
}

class _ParamCellState extends State<_ParamCell> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c, p = widget.p;
    final v = c.value(p.id);
    Widget control;
    if (p.isBool) {
      control = StompSwitch(on: v > .5, size: 50, onChanged: (on) => c.setParam(p, on ? 1 : 0));
    } else if (p.isEnum) {
      control = RotarySelector(choices: p.choices, index: p.choiceIndex(v), accent: widget.accent, onChanged: (i) => c.setParam(p, p.maximum == 0 ? 0 : i / p.maximum));
    } else if (p.isFader) {
      control = Fader(value: v, accent: widget.accent, onChanged: (n) => c.setParam(p, n), onReset: () => c.revertParam(p));
    } else {
      control = Knob(value: v, size: 100, accent: widget.accent, onChanged: (n) => c.setParam(p, n), onReset: () => c.revertParam(p));
    }
    final edited = c.paramEdited(p);
    return RepaintBoundary(
      child: Listener(
      onPointerDown: (_) => setState(() => _active = true),
      onPointerUp: (_) => setState(() => _active = false),
      onPointerCancel: (_) => setState(() => _active = false),
      child: Container(
        width: _cellW,
        height: _cellH,
        margin: const EdgeInsets.all(_cellPad),
        child: Column(children: [
          SizedBox(
            height: 20,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: Text(p.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: Rx.condensed, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Rx.onBlock.withValues(alpha: .85))),
              ),
              // edited since the RIG was saved (double-click the control to revert)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                width: edited ? 6 : 0,
                height: 6,
                margin: EdgeInsets.only(left: edited ? 5 : 0),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Rx.gold, boxShadow: [BoxShadow(color: Rx.gold.withValues(alpha: .6), blurRadius: 4)]),
              ),
            ]),
          ),
          SizedBox(height: 218, child: Center(child: control)),
          const SizedBox(height: 6),
          LcdReadout(p.display(v), color: widget.lcd, width: 96, active: _active),
        ]),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------- OFF / ON scenes
/// The two tones of the RIG, drawn like footswitch scenes. Tap = edit that side.
/// Green LED = the side the pedal is playing.
class SideCards extends StatelessWidget {
  const SideCards({super.key, required this.c, this.compact = false, this.vertical = false});
  final PedalController c;
  final bool compact, vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [_card(0), const SizedBox(height: 8), _card(1)]);
    }
    return Row(children: [
      for (var i = 0; i < 2; i++) ...[
        if (i == 1) const SizedBox(width: 10),
        Expanded(child: _card(i)),
      ],
    ]);
  }

  Widget _card(int i) {
    final editing = c.side == i;
    final sounding = c.pressed != null && c.soundingSide == i;
    final accent = i == 0 ? Rx.gold : Rx.red;
    return GestureDetector(
      onTap: () => c.selectSide(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: editing ? [Color.lerp(Rx.raised, accent, .22)!, Color.lerp(Rx.panel, accent, .08)!] : [Rx.raised, Rx.panel],
            ),
            border: Border.all(color: editing ? accent : (Rx.light ? Rx.line : Colors.black.withValues(alpha: .7)), width: editing ? 2 : 1),
            boxShadow: Rx.shadows([
              const BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4)),
              if (editing) BoxShadow(color: accent.withValues(alpha: .22), blurRadius: 18),
            ]),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(i == 0 ? 'OFF' : 'ON',
                  style: TextStyle(fontFamily: Rx.condensed, fontSize: compact ? 15 : 20, height: 1, fontWeight: FontWeight.w800, fontStyle: Rx.italic, color: accent, letterSpacing: 2, shadows: editing ? Rx.glow(accent, 10) : null)),
            ]),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                layoutBuilder: (current, previous) => Align(alignment: Alignment.centerLeft, child: current),
                transitionBuilder: (child, a) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: child),
                child: Text(c.active[i].name,
                    key: ValueKey('${c.active[i].name}$i'),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 12.5 : 13.5, fontWeight: FontWeight.w600, color: editing ? Rx.text : Rx.dim)),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(message: sounding ? '本体で鳴っている音色' : '', child: JewelLed(on: sounding, color: Rx.green, size: 10)),
          ]),
        ),
      ),
    );
  }
}

/// SAVE RIG: breathes red while there are unsaved edits.
class SaveRigButton extends StatefulWidget {
  const SaveRigButton({super.key, required this.c});
  final PedalController c;
  @override
  State<SaveRigButton> createState() => _SaveRigButtonState();
}

class _SaveRigButtonState extends State<SaveRigButton> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final dirty = c.rigDirty;
    // steady red glow while there are unsaved edits (no endless pulse animation: that kept
    // the whole window repainting 60 times a second)
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: dirty ? Rx.shadows([BoxShadow(color: Rx.red.withValues(alpha: .45), blurRadius: 14)]) : const [],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: Tooltip(
            message: 'RIG を保存（Ctrl+S）',
            waitDuration: const Duration(milliseconds: 700),
            child: FilledButton.icon(
              onPressed: c.busy ? null : c.saveRig,
              style: FilledButton.styleFrom(
                backgroundColor: dirty ? Rx.red : Rx.raised,
                foregroundColor: dirty ? Rx.onAccent : Rx.text,
                side: BorderSide(color: dirty ? Rx.red : Rx.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(dirty ? Icons.save : Icons.save_outlined, size: 20),
              label: Text('SAVE RIG', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 3)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- libraries
// Pages are sized to the space the list gets: every tile is fully visible and selectable
// without scrolling; ◀ ▶ moves between pages (with a slide).
const double _navH = 42, _gap = 6;

Color? get _navInk => Rx.list == ListStyle.tiles ? null : Rx.listInk;

/// A list row written in pencil on the set list (circled in red when selected) or shown in a
/// VFD window (inverted when selected).
Widget _listTile({required bool selected, required VoidCallback? onTap, required String no, required String title, String? sub}) {
  final ink = Rx.listInk;
  const pen = Color(0xFFC0281C);
  if (Rx.list == ListStyle.paper) {
    TextStyle pencil(double size, Color color, [FontWeight w = FontWeight.w400]) =>
        TextStyle(fontFamily: Rx.pencil, fontFamilyFallback: Rx.pencilFallback, fontSize: size, height: 1.1, fontWeight: w, color: color);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
          alignment: Alignment.bottomLeft,
          decoration: selected ? BoxDecoration(border: Border.all(color: pen, width: 2), borderRadius: BorderRadius.circular(18)) : null,
          child: sub != null
              // two ruled lines: RIG name on the first, its tones on the second
              ? Column(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        SizedBox(width: 34, child: Text(no, style: pencil(15, selected ? pen : graphite.withValues(alpha: .55)))),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Text(title, maxLines: 1, style: pencil(21, graphite.withValues(alpha: .92), FontWeight.w700)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 34, bottom: 4),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Text(sub, maxLines: 1, style: pencil(17, graphite.withValues(alpha: .7))),
                        ),
                      ),
                    ),
                  ),
                ])
              : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(width: 34, child: Text(no, style: pencil(14, selected ? pen : graphite.withValues(alpha: .55)))),
            Flexible(
              flex: sub == null ? 1 : 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(title, maxLines: 1, style: pencil(19, graphite.withValues(alpha: .92), FontWeight.w700)),
              ),
            ),
            if (sub != null) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(sub, maxLines: 1, style: pencil(13, graphite.withValues(alpha: .55))),
                ),
              ),
            ],
          ]),
          ),
        ),
      ),
    );
  }
  final fg = selected ? const Color(0xFF0C1614) : ink;
  final glow = !selected ? [Shadow(color: ink.withValues(alpha: .7), blurRadius: 6)] : null;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? ink : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          boxShadow: selected ? [BoxShadow(color: ink.withValues(alpha: .45), blurRadius: 8)] : null,
        ),
        child: Row(children: [
          SizedBox(width: 30, child: Text(no, style: TextStyle(fontFamily: Rx.mono, fontSize: 15, color: fg, shadows: glow))),
          const SizedBox(width: 6),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Rx.mono, fontSize: 15, letterSpacing: .5, color: fg, shadows: glow, fontFamilyFallback: Rx.fallback)),
              if (sub != null)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Rx.mono, fontSize: 11, color: fg.withValues(alpha: .6), fontFamilyFallback: Rx.fallback)),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// A sheet of the set list pad: paper, blue lines under every row, red margin.
class RuledPage extends StatelessWidget {
  const RuledPage({super.key, required this.pitch, required this.child});
  final double pitch;
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: paperColor,
        child: CustomPaint(painter: _RuledLines(pitch), isComplex: true, child: SizedBox.expand(child: child)),
      );
}

const Color paperColor = Color(0xFFF3EFE4);
const Color graphite = Color(0xFF3A3A3E);

class _RuledLines extends CustomPainter {
  const _RuledLines(this.pitch);
  final double pitch;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x553C6EB4)
      ..strokeWidth = 1;
    for (double y = pitch - .5; y < size.height; y += pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(const Offset(34, 0), Offset(34, size.height), Paint()..color = const Color(0x55C0281C)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_RuledLines old) => old.pitch != pitch;
}

/// Turns the page of a spiral-bound pad (binding on the left): going forward the sheet
/// lifts off the pad with its free (right) edge coming up toward you and swings over the
/// binding; going back the previous sheet swings back down onto the pad. The sheet bends
/// while it moves (see [_CurledSheet]), so it looks like paper, not a card.
class PageFlip extends StatelessWidget {
  const PageFlip({super.key, required this.child, required this.forward});
  final Widget child; // must carry a key that changes per page
  final bool forward;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeInOutSine,
        switchOutCurve: Curves.easeInOutSine,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: forward ? [if (current != null) current, ...previous] : [...previous, if (current != null) current],
        ),
        transitionBuilder: (c, anim) {
          final incoming = c.key == child.key;
          if (forward == incoming) return c; // the sheet underneath stays on the pad
          return AnimatedBuilder(
            animation: anim,
            child: c,
            builder: (context, w) => _CurledSheet(t: 1 - anim.value, child: w!),
          );
        },
        child: child,
      );
}

/// A sheet turned by [t] (0 = lying on the pad, 1 = turned over the binding), drawn as a
/// chain of vertical strips hinged to each other: the strips near the binding follow the
/// turn, the free edge lags or leads a little, which gives the soft curl of real paper.
class _CurledSheet extends StatelessWidget {
  const _CurledSheet({required this.t, required this.child});
  final double t;
  final Widget child;

  static const int _n = 7;

  @override
  Widget build(BuildContext context) {
    if (t <= 0.001) return child;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final sw = w / _n;
      final turn = t * math.pi * .62; // ~112° at the end: the sheet leaves over the binding
      final bend = math.sin(t * math.pi) * .55; // curl is strongest mid-turn, none at the ends
      // cumulative angle of strip k: the binding side follows the turn, the free edge curls
      double cum(int k) {
        final f = k / (_n - 1);
        return turn * (1 - bend * .45) + turn * bend * f * f;
      }

      Widget strip(int k) {
        final rel = cum(k) - (k == 0 ? 0 : cum(k - 1));
        final face = math.cos(cum(k)).clamp(-1.0, 1.0);
        return Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()..rotateY(rel),
          child: SizedBox(
            width: sw,
            height: h,
            child: Stack(clipBehavior: Clip.none, children: [
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: w,
                  maxWidth: w,
                  minHeight: h,
                  maxHeight: h,
                  child: Transform.translate(offset: Offset(-k * sw, 0), child: child),
                ),
              ),
              // light falls off as the strip turns away; the back of the sheet is a bit darker
              IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: ((1 - face) * .22).clamp(0.0, .45).toDouble()))),
              if (k + 1 < _n) Positioned(left: sw, top: 0, width: sw, height: h, child: strip(k + 1)),
            ]),
          ),
        );
      }

      return Opacity(
        opacity: t > .9 ? (1 - t) / .1 : 1.0,
        child: Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()..setEntry(3, 2, .0011), // with a positive rotateY the free edge comes toward the viewer
          child: strip(0),
        ),
      );
    });
  }
}

class _PageNav extends StatelessWidget {
  const _PageNav({required this.page, required this.pages, required this.onPage, this.trailing});
  final int page, pages;
  final ValueChanged<int> onPage;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: _navH,
        child: Row(children: [
          const Spacer(),
          IconButton(onPressed: page > 0 ? () => onPage(page - 1) : null, color: _navInk, icon: const Icon(Icons.chevron_left)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < pages; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
                width: i == page ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i == page ? (Rx.list == ListStyle.vfd ? Rx.listInk : Rx.red) : (Rx.list == ListStyle.tiles ? Rx.ledOff : Rx.listInk.withValues(alpha: .25))),
              ),
          ]),
          IconButton(onPressed: page < pages - 1 ? () => onPage(page + 1) : null, color: _navInk, icon: const Icon(Icons.chevron_right)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

Widget _tile({required bool selected, required VoidCallback? onTap, required Widget child, Color? accent}) => _tileBody(selected, onTap, child, accent ?? Rx.gold);

Widget _tileBody(bool selected, VoidCallback? onTap, Widget child, Color accent) => AnimatedContainer(
      duration: const Duration(milliseconds: 190), curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: selected ? [Color.lerp(Rx.raised, accent, .16)!, Color.lerp(Rx.panel, accent, .06)!] : [Rx.raised, Rx.panel],
        ),
        border: Border.all(color: selected ? accent : (Rx.light ? Rx.line : Colors.black.withValues(alpha: .7)), width: selected ? 2 : 1),
        boxShadow: Rx.shadows([
          const BoxShadow(color: Color(0x66000000), blurRadius: 5, offset: Offset(0, 2)),
          if (selected) BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 12),
        ]),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Align(alignment: Alignment.centerLeft, child: child)),
        ),
      ),
    );

class _PagedTiles extends StatefulWidget {
  const _PagedTiles({required this.count, required this.tileH, required this.minColW, required this.page, required this.onPage, required this.tile, this.trailing, this.linePitch});
  final int count, page;
  final double tileH, minColW;
  final double? linePitch; // ruled line spacing on paper (a tile may span several lines)
  final ValueChanged<int> onPage;
  final Widget Function(int index) tile;
  final Widget? trailing;
  @override
  State<_PagedTiles> createState() => _PagedTilesState();
}

class _PagedTilesState extends State<_PagedTiles> {
  int _dir = 1;
  double _dragDx = 0;

  @override
  void didUpdateWidget(_PagedTiles old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) _dir = widget.page > old.page ? 1 : -1;
  }

  void _wheel(PointerSignalEvent e, int p, int pages) {
    if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
      final next = p + (e.scrollDelta.dy > 0 ? 1 : -1);
      if (next >= 0 && next < pages) GestureBinding.instance.pointerSignalResolver.register(e, (_) => widget.onPage(next));
    }
  }

  /// Horizontal swipe turns the page (touch screens). Past the last / first page it moves
  /// on to the next / previous tab (SET LIST <-> TONES), like one continuous list.
  Widget _swipe(Widget child, int p, int pages) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragDx = 0,
        onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          final step = _dragDx < -48 || v < -300 ? 1 : (_dragDx > 48 || v > 300 ? -1 : 0);
          if (step == 0) return;
          final next = p + step;
          if (next >= 0 && next < pages) {
            widget.onPage(next);
            return;
          }
          final tabs = DefaultTabController.maybeOf(context);
          final t = (tabs?.index ?? 0) + step;
          if (tabs != null && t >= 0 && t < tabs.length) tabs.animateTo(t);
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (Rx.list == ListStyle.paper) return _paper(context);
    return LayoutBuilder(builder: (context, box) {
      final cols = math.max(1, ((box.maxWidth + _gap) / (widget.minColW + _gap)).floor());
      final rows = math.max(1, ((box.maxHeight - _navH + _gap) / (widget.tileH + _gap)).floor());
      final per = cols * rows;
      final pages = math.max(1, (widget.count / per).ceil());
      final p = math.min(widget.page, pages - 1);
      final colW = (box.maxWidth - (cols - 1) * _gap) / cols;
      final first = p * per;
      final tiles = Wrap(spacing: _gap, runSpacing: _gap, children: [
        for (var i = first; i < math.min(widget.count, first + per); i++) SizedBox(width: colW, height: widget.tileH, child: widget.tile(i)),
      ]);
      return Column(children: [
        Expanded(
          child: _swipe(Listener(
            onPointerSignal: (e) => _wheel(e, p, pages), // mouse wheel turns the pages
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 270),
                switchInCurve: Curves.easeOutCubic,
                layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
                transitionBuilder: (child, a) =>
                    SlideTransition(position: Tween<Offset>(begin: Offset(.08 * _dir, 0), end: Offset.zero).animate(a), child: child),
                child: Align(key: ValueKey('p$p$per'), alignment: Alignment.topLeft, child: tiles),
              ),
            ),
          ), p, pages),
        ),
        _PageNav(page: p, pages: pages, onPage: widget.onPage, trailing: widget.trailing),
      ]);
    });
  }

  /// Set list pad: the whole sheet (tabs written at the top, the rows, the page number at
  /// the bottom) is one piece of paper, so it turns as a whole. Every row sits on a line.
  Widget _paper(BuildContext context) {
    final pitch = widget.linePitch ?? widget.tileH;
    return LayoutBuilder(builder: (context, box) {
      final rows = math.max(1, ((box.maxHeight - 2 * pitch) / widget.tileH).floor());
      final pages = math.max(1, (widget.count / rows).ceil());
      final p = math.min(widget.page, pages - 1);
      final first = p * rows;
      TextStyle pencil(double size, Color color) => TextStyle(fontFamily: Rx.pencil, fontFamilyFallback: Rx.pencilFallback, fontSize: size, color: color, height: 1.1);
      Widget arrow(IconData icon, int to) => IconButton(
            onPressed: to >= 0 && to < pages ? () => widget.onPage(to) : null,
            icon: Icon(icon, size: 20),
            color: graphite,
            disabledColor: graphite.withValues(alpha: .2),
            visualDensity: VisualDensity.compact,
          );
      final sheet = RuledPage(
        key: ValueKey('p$p$rows'),
        pitch: pitch,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // first line: the tabs, written on the sheet
          SizedBox(
            height: pitch,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const SizedBox(width: 34),
              const _PaperTab(index: 0, label: 'SET LIST'),
              const SizedBox(width: 18),
              const _PaperTab(index: 1, label: 'TONES'),
              const Spacer(),
              if (widget.trailing != null) widget.trailing!,
            ]),
          ),
          for (var i = first; i < math.min(widget.count, first + rows); i++) SizedBox(height: widget.tileH, child: widget.tile(i)),
          // next free line: page number
          SizedBox(
            height: pitch,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              arrow(Icons.chevron_left, p - 1),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('p. ${p + 1} / $pages', style: pencil(15, graphite.withValues(alpha: .6)))),
              arrow(Icons.chevron_right, p + 1),
            ]),
          ),
        ]),
      );
      return _swipe(
          Listener(
            onPointerSignal: (e) => _wheel(e, p, pages),
            // not clipped: the turning sheet lifts off the pad and may swing past its edges
            child: PageFlip(forward: _dir > 0, child: sheet),
          ),
          p,
          pages);
    });
  }
}

/// SET LIST / TONES written at the top of the sheet; the open one is underlined in red.
class _PaperTab extends StatelessWidget {
  const _PaperTab({required this.index, required this.label});
  final int index;
  final String label;
  @override
  Widget build(BuildContext context) {
    final tabs = DefaultTabController.maybeOf(context);
    final on = tabs?.index == index;
    return GestureDetector(
      onTap: () => tabs?.animateTo(index),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.only(bottom: 2),
          decoration: on ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFC0281C), width: 3))) : null,
          child: Text(label, style: TextStyle(fontFamily: Rx.marker, fontSize: 17, height: 1.1, color: on ? graphite : graphite.withValues(alpha: .35))),
        ),
      ),
    );
  }
}

/// Loads RIG [i]; asks first when the current RIG has unsaved edits.
Future<void> openRig(BuildContext context, PedalController c, int i) async {
  if (c.rigDirty) {
    final r = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Rx.panel,
        title: const Text('変更が保存されていません', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('RIG ${c.library.data.selected.toString().padLeft(2, '0')}「${c.library.rigName(c.library.data.selected)}」の編集内容をどうしますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('破棄')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存して切替')),
        ],
      ),
    );
    if (r == null) return;
    if (r) {
      await c.saveRig();
      if (c.rigDirty) return; // save failed: keep the edits
    }
  }
  await c.selectRig(i);
}

/// Puts tone [i] on the side being edited; asks first when that side has knob changes.
Future<void> openTone(BuildContext context, PedalController c, int i) async {
  if (c.sideEdited) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Rx.panel,
        title: const Text('変更が保存されていません', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('編集中の ${c.side == 0 ? 'OFF' : 'ON'} 音色「${c.active[c.side].name}」の変更を破棄して、'
            '「${c.library.data.tones[i].name}」を読み込みますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('破棄して読み込む')),
        ],
      ),
    );
    if (ok != true) return;
  }
  c.loadTone(i);
}

/// 32 RIG presets. Tap = load onto the pedal.
class RigList extends StatelessWidget {
  const RigList({super.key, required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final lib = c.library;
    final lcd = Rx.lcd(c.bass);
    return _PagedTiles(
      count: LibraryData.rigCount,
      // on paper each RIG takes two ruled lines: name, then its OFF / ON tones
      tileH: Rx.list == ListStyle.paper ? 68 : 54,
      linePitch: 34,
      minColW: 300,
      page: c.rigPage,
      onPage: (p) => c.setPage(rig: p),
      tile: (i) {
        final sel = i == lib.data.selected;
        final pair = lib.pair(i);
        if (Rx.list != ListStyle.tiles) {
          return _listTile(
            selected: sel,
            onTap: c.busy ? null : () => openRig(context, c, i),
            no: i.toString().padLeft(2, '0'),
            title: lib.rigName(i),
            sub: '${pair[0].name}  →  ${pair[1].name}',
          );
        }
        return Tooltip(
          message: '${lib.rigName(i)}\nOFF  ${pair[0].name}\nON    ${pair[1].name}',
          waitDuration: const Duration(milliseconds: 900),
          child: _tile(
            selected: sel,
            onTap: c.busy ? null : () => openRig(context, c, i),
            child: Row(children: [
              Container(
                width: 34,
                padding: const EdgeInsets.symmetric(vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .5), borderRadius: BorderRadius.circular(4)),
                child: Text(i.toString().padLeft(2, '0'),
                    style: TextStyle(fontFamily: Rx.condensed, fontSize: 13, fontWeight: FontWeight.w800, color: sel ? lcd : lcd.withValues(alpha: .55), fontFeatures: Rx.tabular, shadows: sel ? Rx.glow(lcd, 6) : null)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lib.rigName(i), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Rx.condensed, fontSize: 14, fontWeight: FontWeight.w800, color: sel ? Rx.gold : Rx.text)),
                  const SizedBox(height: 2),
                  Text('${pair[0].name}  →  ${pair[1].name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Rx.dim)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// 48 tones (32 factory + 16 user). Tap = put on the side being edited.
class ToneList extends StatelessWidget {
  const ToneList({super.key, required this.c, required this.onManage});
  final PedalController c;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final lib = c.library;
    final accent = c.side == 0 ? Rx.gold : Rx.red;
    return _PagedTiles(
      count: LibraryData.toneCount,
      tileH: Rx.list == ListStyle.paper ? 34 : 40,
      minColW: Rx.list == ListStyle.paper ? 1000 : 150,
      page: c.tonePage,
      onPage: (p) => c.setPage(tone: p),
      trailing: IconButton(tooltip: '音色の管理', onPressed: onManage, color: _navInk, icon: const Icon(Icons.tune, size: 20)),
      tile: (i) => Rx.list != ListStyle.tiles
          ? _listTile(selected: i == c.selectedTone, onTap: () => openTone(context, c, i), no: i.toString().padLeft(2, '0'), title: lib.data.tones[i].name)
          : Tooltip(
        message: lib.data.tones[i].name,
        waitDuration: const Duration(milliseconds: 900),
        child: _tile(
          selected: i == c.selectedTone,
          accent: accent,
          onTap: () => openTone(context, c, i),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${i.toString().padLeft(2, '0')}  ', style: TextStyle(color: i >= 32 ? Rx.gold : Rx.faint, fontFeatures: Rx.tabular, fontWeight: FontWeight.w700)),
              TextSpan(text: lib.data.tones[i].name),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
