// Screens: desktop / tablet "hardware" layout and a three-tab phone layout.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import 'editor.dart';
import 'indicators.dart';
import 'panels.dart';
import 'pedalboard.dart';
import 'theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    return _Keys(
      c: c,
      child: ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        backgroundColor: Rx.bg,
        body: Stack(children: [
          const Positioned.fill(child: BrushedBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 1100 && box.maxHeight >= 600 ? _Desktop(c: c) : _Phone(c: c),
            ),
          ),
        ]),
      ),
      ),
    );
  }
}

/// Desktop keys: ← → effect, Space bypass, Ctrl+S SAVE RIG, Tab OFF/ON, Esc releases a focused knob.
class _Keys extends StatefulWidget {
  const _Keys({required this.c, required this.child});
  final PedalController c;
  final Widget child;
  @override
  State<_Keys> createState() => _KeysState();
}

class _KeysState extends State<_Keys> {
  final _focus = FocusNode(debugLabel: 'home-keys');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _step(int d) {
    final c = widget.c;
    final order = c.defaults.order;
    final i = order.indexOf(c.selectedBlock);
    c.selectBlock(order[(i + d + order.length) % order.length]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.space): () => c.toggleBlock(c.selectedBlock),
        const SingleActivator(LogicalKeyboardKey.tab): () => c.selectSide(1 - c.side),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!c.busy && c.rigDirty) c.saveRig();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => _focus.requestFocus(),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: widget.child,
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.c});
  final PedalController c;
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic,
        child: c.status.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.status, style: TextStyle(fontSize: 12, color: Rx.dim))),
      );
}

class _Library extends StatelessWidget {
  const _Library({required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final style = Rx.list;
    final ink = Rx.listInk;
    final Widget tabs = switch (style) {
      ListStyle.tiles => Well(
          padding: const EdgeInsets.all(3),
          child: TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(Rx.redDark, Rx.red, .12)!, Rx.redDark]),
              border: Border.all(color: Rx.red.withValues(alpha: .6)),
              boxShadow: [BoxShadow(color: Rx.red.withValues(alpha: .2), blurRadius: 10)],
            ),
            labelStyle: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 13),
            tabs: const [Tab(text: 'RIG', height: 34), Tab(text: 'TONE', height: 34)],
          ),
        ),
      ListStyle.vfd => TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: ink.withValues(alpha: .5), blurRadius: 8)]),
          labelColor: const Color(0xFF0C1614),
          unselectedLabelColor: ink.withValues(alpha: .5),
          labelStyle: TextStyle(fontFamily: Rx.mono, letterSpacing: 3, fontSize: 14),
          tabs: const [Tab(text: 'RIG', height: 30), Tab(text: 'TONE', height: 30)],
        ),
      ListStyle.paper => TabBar(
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: Color(0xFFC0281C), width: 3)),
          labelColor: ink,
          unselectedLabelColor: ink.withValues(alpha: .4),
          labelStyle: const TextStyle(fontFamily: Rx.marker, fontSize: 18, letterSpacing: 1),
          tabs: const [Tab(text: 'SET LIST', height: 38), Tab(text: 'TONES', height: 38)],
        ),
    };
    final body = Column(children: [
      // on paper the tabs are written on the sheet itself (they turn with the page)
      if (style != ListStyle.paper) ...[tabs, const SizedBox(height: 8)],
      Expanded(
        child: style == ListStyle.paper
            // the set list pad: switching SET LIST / TONES turns the page
            ? _PaperTabs(pages: [RigList(c: c), ToneList(c: c, onManage: () => showToneManager(context, c))])
            : TabBarView(children: [
                RigList(c: c),
                ToneList(c: c, onManage: () => showToneManager(context, c)),
              ]),
      ),
    ]);
    return DefaultTabController(
      length: 2,
      child: switch (style) {
        ListStyle.tiles => body,
        // dark display window of a hi-fi deck
        ListStyle.vfd => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1614),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF1E2023), width: 3),
              boxShadow: [const BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 4)), BoxShadow(color: Colors.white.withValues(alpha: .5), offset: const Offset(0, 1))],
            ),
            child: body,
          ),
        // a set list taped to the floor
        ListStyle.paper => Transform.rotate(
            angle: -.006,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(30, 4, 10, 4),
                decoration: const BoxDecoration(
                  color: paperColor,
                  boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 8))],
                ),
                child: body,
              ),
              // spiral binding on the left edge
              const Positioned(left: -9, top: 0, bottom: 0, width: 36, child: IgnorePointer(child: CustomPaint(painter: _SpiralBinding(), isComplex: true))),
            ]),
          ),
      },
    );
  }
}

/// Wire coils through punched holes along the left edge of the pad.
class _SpiralBinding extends CustomPainter {
  const _SpiralBinding();
  @override
  void paint(Canvas canvas, Size size) {
    const hx = 27.0; // hole centre (the paper starts at x = 9)
    final hole = Paint()..color = const Color(0xFF26221E);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final dark = Paint()
      ..color = const Color(0xFF55595E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final wire = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF8A8F95), Color(0xFFF4F6F8), Color(0xFF9EA3A8)]).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (double y = 14; y < size.height - 6; y += 17) {
      canvas.drawCircle(Offset(hx, y), 3.4, hole);
      final loop = Path()
        ..moveTo(hx - 1, y + 1.5)
        ..cubicTo(hx - 8, y - 9, 1, y - 8, 2, y + 2)
        ..cubicTo(3, y + 7, 8, y + 7, 12, y + 4);
      canvas.drawPath(loop.shift(const Offset(1, 2)), shadow);
      canvas.drawPath(loop, dark);
      canvas.drawPath(loop, wire);
    }
  }

  @override
  bool shouldRepaint(_SpiralBinding old) => false;
}

/// SET LIST / TONES pages of the pad, switched with a page turn (follows the tab bar).
class _PaperTabs extends StatefulWidget {
  const _PaperTabs({required this.pages});
  final List<Widget> pages;
  @override
  State<_PaperTabs> createState() => _PaperTabsState();
}

class _PaperTabsState extends State<_PaperTabs> {
  TabController? _tabs;
  int _index = 0, _prev = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = DefaultTabController.of(context);
    if (t != _tabs) {
      _tabs?.removeListener(_changed);
      _tabs = t..addListener(_changed);
      _index = t.index;
    }
  }

  void _changed() {
    final i = _tabs!.index;
    if (i != _index) {
      setState(() {
        _prev = _index;
        _index = i;
      });
    }
  }

  @override
  void dispose() {
    _tabs?.removeListener(_changed);
    super.dispose();
  }

  @override
  // not clipped: the turning sheet lifts off the pad and may swing past its edges
  Widget build(BuildContext context) => PageFlip(
        forward: _index > _prev,
        child: ColoredBox(key: ValueKey(_index), color: paperColor, child: widget.pages[_index]),
      );
}

// ---------------------------------------------------------------- desktop / tablet
// Every theme keeps the same controls and gestures but arranges them like its hardware:
//   STUDIO RACK    stacked rack units (head unit / pedal strip / library + faceplate / live rack)
//   STUDIO CONSOLE meter bridge with VU meters, channel strip, faceplate left + scribble list right
//   RETRO HI-FI    component deck: display on top, VFD list + faceplate, key row and tools at the bottom
//   REAL BOARD     the board on top, set list | close-up of the pedal | scenes + rack tools
class _Desktop extends StatelessWidget {
  const _Desktop({required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 860;
    final body = switch (Rx.t.id) {
      RxThemeId.studio => _rack(short),
      RxThemeId.console => _console(short),
      RxThemeId.hifi => _hifi(short),
      RxThemeId.board => _board(short),
    };
    return Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 12), child: body);
  }

  Widget _head(bool short, {bool footswitch = true, Widget? extra}) => Row(children: [
        if (footswitch) ...[FootswitchView(pressed: c.connected ? c.physical : null, scale: short ? .8 : 1), const SizedBox(width: 10)],
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Logo(size: 26),
          const SizedBox(height: 10),
          ModeToggle(c: c),
        ]),
        const SizedBox(width: 20),
        if (extra != null) ...[extra, const SizedBox(width: 16)],
        Expanded(child: HeadUnitDisplay(c: c)),
        const SizedBox(width: 14),
        BluetoothBox(c: c),
        SettingsMenu(c: c),
      ]);

  Widget _pedalStrip(double height, double pedalW) => Plate(
        padding: Rx.t.frame == null ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : const EdgeInsets.all(7),
        color: Rx.t.frame,
        child: Pedalboard(c: c, height: height, pedalW: pedalW),
      );

  Widget _library({bool title = true}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title) ...[SectionTitle('RIG PRESETS', size: 13, color: Rx.gold), const SizedBox(height: 8)],
        Expanded(child: _Library(c: c)),
      ]);

  Widget _editor() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: SideCards(c: c, compact: true)),
          const SizedBox(width: 12),
          SizedBox(width: 190, child: SaveRigButton(c: c)),
        ]),
        _StatusLine(c: c),
        Expanded(child: EffectFaceplate(c: c)),
      ]);

  // ---- STUDIO RACK: stacked rack units
  Widget _rack(bool short) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(short),
        const SizedBox(height: 10),
        _pedalStrip(short ? 92 : 104, 88),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 400, child: _library()),
            const SizedBox(width: 20),
            Expanded(child: _editor()),
          ]),
        ),
        const SizedBox(height: 10),
        LiveRack(c: c),
      ]);

  // ---- STUDIO CONSOLE: meter bridge, channel strip, faceplate | scribble list
  Widget _console(bool short) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Plate(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          color: Rx.chassis,
          child: _head(
            short,
            footswitch: false,
            // rebuilt on every level report so the needles wake up (they sleep when at rest)
            extra: ListenableBuilder(
              listenable: c.meters,
              builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                VuMeter(label: 'IN', meter: c.meters.input, width: short ? 120 : 140, height: short ? 70 : 80),
                const SizedBox(width: 8),
                VuMeter(label: 'OUT', meter: c.meters.output, width: short ? 120 : 140, height: short ? 70 : 80),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _pedalStrip(short ? 96 : 112, 84),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _editor()),
            const SizedBox(width: 18),
            SizedBox(width: 360, child: _library()),
          ]),
        ),
        const SizedBox(height: 10),
        LiveRack(c: c, meters: false),
      ]);

  // ---- RETRO HI-FI: deck with the display on top and the key row near the player
  Widget _hifi(bool short) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(short),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 360, child: _library(title: false)),
            const SizedBox(width: 18),
            Expanded(child: _editor()),
          ]),
        ),
        const SizedBox(height: 10),
        _pedalStrip(short ? 86 : 96, 90),
        const SizedBox(height: 10),
        LiveRack(c: c),
      ]);

  // ---- REAL BOARD: board on top, set list | close-up | scenes + rack tools
  Widget _board(bool short) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(short, footswitch: false),
        const SizedBox(height: 10),
        _pedalStrip(short ? 170 : 198, 82),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 320, child: _library(title: false)),
            const SizedBox(width: 18),
            Expanded(child: EffectFaceplate(c: c)),
            const SizedBox(width: 18),
            SizedBox(
              width: 370,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SideCards(c: c, compact: true, vertical: true),
                const SizedBox(height: 10),
                SizedBox(height: 50, child: SaveRigButton(c: c)),
                _StatusLine(c: c),
                const SizedBox(height: 10),
                Expanded(child: SingleChildScrollView(child: LiveRack(c: c, vertical: true))),
              ]),
            ),
          ]),
        ),
      ]);
}

// ---------------------------------------------------------------- phone
class _Phone extends StatefulWidget {
  const _Phone({required this.c});
  final PedalController c;
  @override
  State<_Phone> createState() => _PhoneState();
}

class _PhoneState extends State<_Phone> {
  int _tab = 1;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final pages = [_rigPage(c), _editPage(c), _livePage(c)];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 0, 2),
        child: Row(children: [
          FootswitchView(pressed: c.connected ? c.physical : null, scale: .5),
          const SizedBox(width: 6),
          const Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Logo(size: 20))),
          const Spacer(),
          _LinkChip(c: c),
          SettingsMenu(c: c),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
        child: GestureDetector(onTap: () => setState(() => _tab = 0), child: HeadUnitDisplay(c: c, compact: true)),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
          transitionBuilder: (child, a) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: child),
          child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
        ),
      ),
      _BottomTabs(index: _tab, onTap: (i) => setState(() => _tab = i)),
    ]);
  }

  Widget _rigPage(PedalController c) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [SectionTitle('RIG PRESETS', color: Rx.gold), const Spacer(), ModeToggle(c: c, compact: true)]),
          const SizedBox(height: 10),
          SideCards(c: c, compact: true),
          const SizedBox(height: 10),
          SaveRigButton(c: c),
          _StatusLine(c: c),
          const SizedBox(height: 10),
          Expanded(child: _Library(c: c)),
        ]),
      );

  Widget _editPage(PedalController c) => Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 4), child: SideCards(c: c, compact: true)),
        Pedalboard(c: c, pedalW: 74, height: Rx.t.pedal == PedalStyle.stomp ? 168 : 92),
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(2, 2, 2, 2), child: EffectFaceplate(c: c))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 6), child: SaveRigButton(c: c)),
      ]);

  Widget _livePage(PedalController c) => ListView(padding: const EdgeInsets.all(12), children: [
        LiveRack(c: c, vertical: true),
        BluetoothBox(c: c, expand: true),
      ]);
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;
  static const _items = [(Icons.library_music, 'RIG'), (Icons.tune, 'EDIT'), (Icons.graphic_eq, 'LIVE')];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Rx.raised, Rx.chassis]),
        border: Border(top: BorderSide(color: Rx.line)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / _items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: w * index + w * .25,
            width: w * .5,
            top: 0,
            height: 3,
            child: Container(decoration: BoxDecoration(color: Rx.red, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: Rx.red.withValues(alpha: .8), blurRadius: 10)])),
          ),
          Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedScale(
                      scale: i == index ? 1.12 : 1,
                      duration: const Duration(milliseconds: 190), curve: Curves.easeOutCubic,
                      child: Icon(_items[i].$1, color: i == index ? Rx.text : Rx.faint, size: 22),
                    ),
                    const SizedBox(height: 3),
                    Text(_items[i].$2, style: TextStyle(fontFamily: Rx.condensed, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: i == index ? Rx.text : Rx.faint)),
                  ]),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Connection state chip; opens the Bluetooth sheet.
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final s = c.linkState;
    return ActionChip(
      avatar: BlinkLed(color: linkColor(s), blink: s == LinkState.scanning || s == LinkState.connecting, size: 8),
      label: Text(linkText(s), style: TextStyle(fontSize: 12, color: linkColor(s))),
      backgroundColor: Rx.raised,
      side: BorderSide(color: Rx.line),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Rx.bg,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(listenable: c, builder: (_, __) => BluetoothBox(c: c, expand: true)),
          ),
        ),
      ),
    );
  }
}
