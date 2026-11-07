// REDLINE FX visual language. Four selectable themes share one layout:
//   STUDIO RACK   dark anodised hardware, red redline accent, amber LCD (default)
//   STUDIO CONSOLE blue-grey mixing desk, coloured-cap knobs, green VFD
//   RETRO HI-FI   silver 80s audio gear with walnut cheeks, teal VFD
//   REAL BOARD    a real pedalboard: carpet, stompboxes, patch cables, tape labels
// Widgets read the active theme through the static getters of [Rx]; switching the theme
// rebuilds the whole tree (see [RxThemes]).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum RxThemeId { studio, console, hifi, board }

enum KnobStyle { studio, cap, silver, dome }

enum PedalStyle { anodized, module, key, stomp }

enum Backdrop { rack, brushed, flat, silver, warm }

/// How the RIG / TONE lists are drawn: tiles, a dark VFD window, or a paper set list.
enum ListStyle { tiles, vfd, paper }

class RxPalette {
  const RxPalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.brightness,
    required this.bgTop,
    required this.bg,
    required this.chassis,
    required this.panel,
    required this.raised,
    required this.line,
    required this.red,
    required this.redDeep,
    required this.redDark,
    required this.gold,
    required this.text,
    required this.dim,
    required this.faint,
    required this.green,
    required this.warn,
    required this.lcdGuitar,
    required this.lcdBass,
    required this.ledOff,
    required this.onBlock,
    required this.onAccent,
    required this.well,
    required this.pedalOff,
    required this.boardSurface,
    required this.blocks,
    required this.body,
    required this.condensed,
    required this.mono,
    required this.italic,
    required this.knob,
    required this.pedal,
    required this.backdrop,
    this.list = ListStyle.tiles,
    this.frame,
    this.plateScrews = false,
    this.radius = 12,
    this.display,
  });

  final RxThemeId id;
  final String name, subtitle;
  final Brightness brightness;
  final Color bgTop, bg, chassis, panel, raised, line;
  final Color red, redDeep, redDark, gold, text, dim, faint, green, warn;
  final Color lcdGuitar, lcdBass, ledOff;
  final Color onBlock; // text / marks printed on an effect enclosure
  final Color onAccent; // text on a filled red button
  final Color well; // recessed area tint
  final Color pedalOff; // a bypassed pedal is blended toward this
  final Color boardSurface; // what the pedals stand on
  final List<Color> blocks; // [dynamics, gain, amp, mod/pitch, time, tone/output, filter/lo-fi]
  final String body, condensed, mono;
  final bool italic;
  final KnobStyle knob;
  final PedalStyle pedal;
  final Backdrop backdrop;
  final ListStyle list;
  final Color? frame; // pedalboard frame (null = panel)
  final bool plateScrews; // every plate is a rack unit with corner screws
  final double radius; // corner radius of plates
  final String? display; // logo / big titles (null = condensed)
}

abstract final class RxPalettes {
  static const studio = RxPalette(
    id: RxThemeId.studio,
    name: 'STUDIO RACK',
    subtitle: '19 インチラックの黒い機材と赤いライン（標準）',
    brightness: Brightness.dark,
    bgTop: Color(0xFF0B0C0E),
    bg: Color(0xFF040405),
    chassis: Color(0xFF0C0D0F),
    panel: Color(0xFF131417),
    raised: Color(0xFF1C1D21),
    line: Color(0xFF2C2E33),
    red: Color(0xFFFF3B2F),
    redDeep: Color(0xFFB0141C),
    redDark: Color(0xFF3A0E12),
    gold: Color(0xFFF2B544),
    text: Color(0xFFF3F1EC),
    dim: Color(0xFF8E9096),
    faint: Color(0xFF55575D),
    green: Color(0xFF3FE07A),
    warn: Color(0xFFFFB547),
    lcdGuitar: Color(0xFFFF5A3C),
    lcdBass: Color(0xFF4FD8FF),
    ledOff: Color(0xFF2A1A1C),
    onBlock: Colors.white,
    onAccent: Color(0xFFF3F1EC),
    well: Color(0x80000000),
    pedalOff: Color(0xFF17181B),
    boardSurface: Color(0xFF131417),
    blocks: [Color(0xFF26282D), Color(0xFF4A1519), Color(0xFF2E2622), Color(0xFF26243A), Color(0xFF1D2C31), Color(0xFF2B2D31), Color(0xFF33291D)],
    body: 'Barlow',
    condensed: 'ChakraPetch',
    mono: 'ShareTechMono',
    italic: false,
    knob: KnobStyle.studio,
    pedal: PedalStyle.anodized,
    backdrop: Backdrop.rack,
    plateScrews: true,
    radius: 5,
    display: 'ChakraPetch',
  );

  static const console = RxPalette(
    id: RxThemeId.console,
    name: 'STUDIO CONSOLE',
    subtitle: 'ヴィンテージのミキシング卓',
    brightness: Brightness.dark,
    bgTop: Color(0xFF3A4147),
    bg: Color(0xFF272C31),
    chassis: Color(0xFF363D43),
    panel: Color(0xFF444C53),
    raised: Color(0xFF555E66),
    line: Color(0xFF15181B),
    red: Color(0xFFE0442E),
    redDeep: Color(0xFFA8321F),
    redDark: Color(0xFF3A1A16),
    gold: Color(0xFFFFD98A),
    text: Color(0xFFF4F1EA),
    dim: Color(0xFFAEB6BC),
    faint: Color(0xFF7D868D),
    green: Color(0xFF7FE0A0),
    warn: Color(0xFFFFB547),
    lcdGuitar: Color(0xFF8DFFC6),
    lcdBass: Color(0xFF9CC8FF),
    ledOff: Color(0xFF2A3035),
    onBlock: Color(0xFFF4F1EA),
    onAccent: Colors.white,
    well: Color(0x40000000),
    pedalOff: Color(0xFF30363B),
    boardSurface: Color(0xFF2C3237),
    blocks: [Color(0xFF56626B), Color(0xFF6B5856), Color(0xFF635A50), Color(0xFF585A6B), Color(0xFF52646A), Color(0xFF5E666D), Color(0xFF635E50)],
    body: 'BarlowSemiCondensed',
    condensed: 'BarlowSemiCondensed',
    mono: 'DMMono',
    italic: false,
    knob: KnobStyle.cap,
    pedal: PedalStyle.module,
    backdrop: Backdrop.flat,
    radius: 3,
    display: 'BarlowSemiCondensed',
  );

  static const hifi = RxPalette(
    id: RxThemeId.hifi,
    name: 'RETRO HI-FI',
    subtitle: '80 年代のオーディオ機器（銀と黒）',
    brightness: Brightness.light,
    bgTop: Color(0xFFA9AEB3),
    bg: Color(0xFF7E848A),
    chassis: Color(0xFF9DA2A7),
    panel: Color(0xFFBDC1C5),
    raised: Color(0xFFD3D6D9),
    line: Color(0xFF6E7378),
    red: Color(0xFFD2361F),
    redDeep: Color(0xFFB52A15),
    redDark: Color(0xFF2A2C30),
    gold: Color(0xFFE08A1E),
    text: Color(0xFF1E2023),
    dim: Color(0xFF41454A),
    faint: Color(0xFF63686D),
    green: Color(0xFF2F9E55),
    warn: Color(0xFFE08A1E),
    lcdGuitar: Color(0xFF5FF3D2),
    lcdBass: Color(0xFFFFA53A),
    ledOff: Color(0xFF6E5A55),
    onBlock: Color(0xFF1E2023),
    onAccent: Colors.white,
    well: Color(0x1F000000),
    pedalOff: Color(0xFF8A8F94),
    boardSurface: Color(0xFF1D1F22),
    blocks: [Color(0xFFC3C8CD), Color(0xFFCDC0BC), Color(0xFFCEC5B8), Color(0xFFC3C2CE), Color(0xFFBCC7C9), Color(0xFFC7CACD), Color(0xFFCEC8B8)],
    body: 'Barlow',
    condensed: 'SairaCondensed',
    mono: 'ShareTechMono',
    italic: false,
    knob: KnobStyle.silver,
    pedal: PedalStyle.key,
    backdrop: Backdrop.silver,
    list: ListStyle.vfd,
    frame: Color(0xFF26282B),
    radius: 2,
    display: 'Michroma',
  );

  static const board = RxPalette(
    id: RxThemeId.board,
    name: 'REAL BOARD',
    subtitle: '本物のエフェクターボードとパッチケーブル',
    brightness: Brightness.dark,
    bgTop: Color(0xFF2E2A26),
    bg: Color(0xFF161412),
    chassis: Color(0xFF1F1C1A),
    panel: Color(0xFF2A2724),
    raised: Color(0xFF36322E),
    line: Color(0xFF4A453F),
    red: Color(0xFFE2402F),
    redDeep: Color(0xFFA8261F),
    redDark: Color(0xFF3A1A16),
    gold: Color(0xFFF2B544),
    text: Color(0xFFECE8E1),
    dim: Color(0xFFA39D93),
    faint: Color(0xFF6F695F),
    green: Color(0xFF3FE07A),
    warn: Color(0xFFFFB547),
    lcdGuitar: Color(0xFFFFB547),
    lcdBass: Color(0xFF4FD8FF),
    ledOff: Color(0xFF3A1210),
    onBlock: Colors.white,
    onAccent: Color(0xFFF4F0E8),
    well: Color(0x61000000),
    pedalOff: Color(0xFF2E2B28),
    boardSurface: Color(0xFF151515),
    blocks: [Color(0xFF4A525C), Color(0xFF6A3438), Color(0xFF54463A), Color(0xFF48465C), Color(0xFF3A5054), Color(0xFF50545A), Color(0xFF5A5040)],
    body: 'Barlow',
    condensed: 'BarlowCondensed',
    mono: 'ShareTechMono',
    italic: false,
    knob: KnobStyle.dome,
    pedal: PedalStyle.stomp,
    backdrop: Backdrop.warm,
    list: ListStyle.paper,
    frame: Color(0xFFA9ADB2),
    display: 'BebasNeue',
  );

  static const List<RxPalette> all = [studio, console, hifi, board];

  static RxPalette of(RxThemeId id) => all.firstWhere((p) => p.id == id, orElse: () => studio);
}

/// The active theme: loaded at start, saved in the app's support folder (theme.txt).
abstract final class RxThemes {
  static final ValueNotifier<RxThemeId> current = ValueNotifier<RxThemeId>(RxThemeId.studio);

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}theme.txt');

  static Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final name = (await f.readAsString()).trim();
        for (final v in RxThemeId.values) {
          if (v.name == name) _apply(v);
        }
      }
    } catch (_) {}
  }

  static Future<void> set(RxThemeId id) async {
    if (id == current.value) return;
    _apply(id);
    try {
      await (await _file()).writeAsString(id.name);
    } catch (_) {}
  }

  static void _apply(RxThemeId id) {
    Rx.t = RxPalettes.of(id);
    current.value = id;
  }
}

abstract final class Rx {
  static RxPalette t = RxPalettes.studio;

  static Color get bgTop => t.bgTop;
  static Color get bg => t.bg;
  static Color get chassis => t.chassis;
  static Color get panel => t.panel;
  static Color get raised => t.raised;
  static Color get line => t.line;
  static Color get red => t.red;
  static Color get redDeep => t.redDeep;
  static Color get redDark => t.redDark;
  static Color get gold => t.gold;
  static Color get text => t.text;
  static Color get dim => t.dim;
  static Color get faint => t.faint;
  static Color get green => t.green;
  static Color get amber => t.warn;
  static Color get cyan => t.lcdBass;
  static Color get ledOff => t.ledOff;
  static Color get onBlock => t.onBlock;
  static Color get onAccent => t.onAccent;
  static Color get well => t.well;
  static bool get light => t.brightness == Brightness.light;
  static ListStyle get list => t.list;

  /// Ink of the RIG / TONE list (paper: pen, VFD: phosphor, tiles: text).
  static Color get listInk => switch (t.list) {
        ListStyle.paper => const Color(0xFF2A2622),
        ListStyle.vfd => t.lcdGuitar,
        ListStyle.tiles => t.text,
      };

  /// Enclosure colour of each effect block (index = block id).
  static List<Color> get blockColors {
    final f = t.blocks; // dynamics, gain, amp, mod, time, tone, filter
    return [f[0], f[0], f[1], f[3], f[4], f[4], f[5], f[5], f[6], f[1], f[3], f[5], f[5], f[6], f[6], f[2], f[0], f[3]];
    // Gate Comp Drive Mod Delay Reverb EQ Cab Wah Boost Octave Output GEQ Crusher Slicer Amp Swell Pitch
  }

  static Color block(int b) {
    final c = blockColors;
    return c[b % c.length];
  }

  /// LCD / display colour for the instrument mode.
  static Color lcd(bool bass) => bass ? t.lcdBass : t.lcdGuitar;

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // Fonts (bundled, SIL OFL / Apache). Japanese falls back to the system UI font.
  static String get body => t.body;
  static String get condensed => t.condensed;
  static String get mono => t.mono;
  static const String marker = 'PermanentMarker';
  static String get display => t.display ?? t.condensed;

  /// Wide display faces are set smaller so titles keep their width.
  static double get displayScale => switch (t.display) {
        'Michroma' => .72,
        'BebasNeue' => 1.15,
        _ => 1.0,
      };

  /// Pencil handwriting for the REAL BOARD set list (Latin: Kalam, Japanese: Yomogi).
  static const String pencil = 'Kalam';
  static const List<String> pencilFallback = ['Yomogi', 'Yu Gothic UI', 'Meiryo', 'Hiragino Sans'];
  static FontStyle get italic => t.italic ? FontStyle.italic : FontStyle.normal;
  static const List<String> fallback = ['Yu Gothic UI', 'Meiryo', 'Hiragino Sans', 'Noto Sans JP', 'Noto Sans CJK JP'];

  static List<Shadow> glow(Color c, [double r = 8]) => [Shadow(color: c.withValues(alpha: .75), blurRadius: r)];

  /// Blur for glows drawn in painters.
  static MaskFilter? blur(double sigma) => MaskFilter.blur(BlurStyle.normal, sigma);

  /// Soft drop shadow.
  static List<BoxShadow> shadows(List<BoxShadow> s) => s;
}

ThemeData buildTheme() {
  final p = Rx.t;
  final dark = p.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: p.red, brightness: p.brightness).copyWith(
    primary: p.red,
    onPrimary: p.onAccent,
    secondary: p.gold,
    surface: p.panel,
    onSurface: p.text,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final base = dark ? ThemeData.dark() : ThemeData.light();
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: p.body,
    fontFamilyFallback: Rx.fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    dividerColor: p.line,
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: p.body, fontFamilyFallback: Rx.fallback),
    iconTheme: IconThemeData(color: p.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: p.redDeep, foregroundColor: p.onAccent, shape: shape, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.raised,
        side: BorderSide(color: p.line),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.red)),
    tabBarTheme: TabBarThemeData(labelColor: p.text, unselectedLabelColor: p.dim, indicatorColor: p.red, dividerColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: dark ? const Color(0xFF5A1A20) : const Color(0xFF3A2020), contentTextStyle: const TextStyle(color: Color(0xFFF1EEE8))),
    sliderTheme: SliderThemeData(activeTrackColor: p.red, thumbColor: p.text, inactiveTrackColor: p.line),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 700)),
    popupMenuTheme: PopupMenuThemeData(color: p.raised),
    dialogTheme: DialogThemeData(backgroundColor: p.panel),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.panel),
  );
}

/// Silk-screened section label.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.size = 13, this.color});
  final String text;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontFamily: Rx.condensed, color: color ?? Rx.dim, fontSize: size * 1.12, fontWeight: FontWeight.w700, letterSpacing: size * .2));
}

/// Anodised plate: light top edge, dark bottom, soft drop shadow.
class Plate extends StatelessWidget {
  const Plate({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius, this.color, this.screws = false});
  final Widget child;
  final EdgeInsets padding;
  final double? radius;
  final Color? color;
  final bool screws;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Rx.panel;
    final radius = this.radius ?? Rx.t.radius;
    final light = Rx.light;
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, light ? .35 : .06)!, color, Color.lerp(color, Colors.black, light ? .12 : .25)!],
          stops: const [0, .35, 1],
        ),
        border: Border.all(color: light ? Rx.line : Colors.black.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: light ? .28 : .6), blurRadius: 14, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.white.withValues(alpha: light ? .6 : .08), blurRadius: 0, spreadRadius: -1, offset: const Offset(0, -1)),
        ],
      ),
      child: child,
    );
    if (!screws && !Rx.t.plateScrews) return body;
    return Stack(children: [
      body,
      for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
        Positioned.fill(child: Align(alignment: a, child: const Padding(padding: EdgeInsets.all(6), child: Screw(size: 8)))),
    ]);
  }
}

/// Recessed well (for displays and control groups).
class Well extends StatelessWidget {
  const Well({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.radius = 8});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Rx.light ? Colors.black.withValues(alpha: .08) : Colors.black.withValues(alpha: .35),
          border: Border.all(color: Rx.light ? Rx.line : Colors.black.withValues(alpha: .6)),
          boxShadow: const [BoxShadow(color: Color(0x0FFFFFFF), offset: Offset(0, 1))],
        ),
        child: child,
      );
}

class Screw extends StatelessWidget {
  const Screw({super.key, this.size = 12, this.angle = .6});
  final double size, angle;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ScrewPainter(angle)),
      );
}

class _ScrewPainter extends CustomPainter {
  _ScrewPainter(this.angle);
  final double angle;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD5D9DE), Color(0xFF5D636B)]).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..color = Colors.black54);
    final d = Offset(math.cos(angle), math.sin(angle)) * r * .7;
    canvas.drawLine(c - d, c + d, Paint()..color = Colors.black87..strokeWidth = math.max(1, r * .28));
  }

  @override
  bool shouldRepaint(_ScrewPainter old) => old.angle != angle;
}

/// Theme backdrop (painted once): brushed metal, flat desk, silver with walnut cheeks, or warm room.
class BrushedBackground extends StatelessWidget {
  const BrushedBackground({super.key});
  @override
  Widget build(BuildContext context) => CachedPaint(painter: _BackdropPainter(Rx.t), cacheKey: Rx.t.id);
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.p);
  final RxPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.bgTop, p.bg]).createShader(rect));
    final rnd = math.Random(7);
    final line = Paint()..strokeWidth = 1;
    switch (p.backdrop) {
      case Backdrop.rack:
        // black brushed rack cabinet with rails and square cage-nut holes at both sides
        for (double y = 0; y < size.height; y += 2) {
          line.color = Colors.white.withValues(alpha: rnd.nextDouble() * .014);
          final x0 = rnd.nextDouble() * size.width * .3;
          canvas.drawLine(Offset(x0, y), Offset(x0 + size.width * (.4 + rnd.nextDouble() * .6), y), line);
        }
        _vignette(canvas, rect, .5);
        const w = 12.0;
        for (final left in [true, false]) {
          final r = left ? Rect.fromLTWH(0, 0, w, size.height) : Rect.fromLTWH(size.width - w, 0, w, size.height);
          canvas.drawRect(r, Paint()..shader = const LinearGradient(colors: [Color(0xFF2A2C30), Color(0xFF4A4D52), Color(0xFF1C1D20)]).createShader(r));
          final hole = Paint()..color = const Color(0xFF020203);
          for (double y = 8; y < size.height; y += 14.8) {
            canvas.drawRect(Rect.fromCenter(center: Offset(r.center.dx, y), width: 5, height: 5), hole);
          }
        }
        // red pinstripe along the top, like a rack unit's trim
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), Paint()..color = p.red.withValues(alpha: .55));
      case Backdrop.brushed:
        for (double y = 0; y < size.height; y += 2) {
          line.color = Colors.white.withValues(alpha: rnd.nextDouble() * .018);
          final x0 = rnd.nextDouble() * size.width * .3;
          canvas.drawLine(Offset(x0, y), Offset(x0 + size.width * (.4 + rnd.nextDouble() * .6), y), line);
        }
        _vignette(canvas, rect, .55);
      case Backdrop.flat:
        for (double y = 0; y < size.height; y += 3) {
          line.color = Colors.black.withValues(alpha: rnd.nextDouble() * .05);
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        _vignette(canvas, rect, .35);
      case Backdrop.silver:
        for (double y = 0; y < size.height; y += 1.5) {
          line.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: rnd.nextDouble() * .06);
          final x0 = rnd.nextDouble() * size.width * .2;
          canvas.drawLine(Offset(x0, y), Offset(x0 + size.width * (.5 + rnd.nextDouble() * .5), y), line);
        }
        // walnut cheeks
        const w = 12.0;
        for (final left in [true, false]) {
          final r = left ? Rect.fromLTWH(0, 0, w, size.height) : Rect.fromLTWH(size.width - w, 0, w, size.height);
          canvas.drawRect(
            r,
            Paint()
              ..shader = LinearGradient(
                colors: left ? const [Color(0xFF3A2213), Color(0xFF6B4024), Color(0xFF4A2B17)] : const [Color(0xFF4A2B17), Color(0xFF6B4024), Color(0xFF3A2213)],
              ).createShader(r),
          );
          final grain = Paint()..strokeWidth = .8;
          for (double y = 0; y < size.height; y += 5) {
            grain.color = Colors.black.withValues(alpha: .08 + rnd.nextDouble() * .12);
            canvas.drawLine(Offset(r.left + rnd.nextDouble() * w, y), Offset(r.left + rnd.nextDouble() * w, y + 18), grain);
          }
        }
      case Backdrop.warm:
        canvas.drawRect(
          rect,
          Paint()..shader = RadialGradient(center: const Alignment(0, -.4), radius: 1.1, colors: [const Color(0xFF3A342E).withValues(alpha: .6), Colors.transparent]).createShader(rect),
        );
        _vignette(canvas, rect, .6);
    }
  }

  void _vignette(Canvas canvas, Rect rect, double a) => canvas.drawRect(
        rect,
        Paint()..shader = RadialGradient(center: const Alignment(0, -.3), radius: 1.2, colors: [Colors.transparent, Colors.black.withValues(alpha: a)]).createShader(rect),
      );

  @override
  bool shouldRepaint(_BackdropPainter old) => old.p.id != p.id;
}

/// Fine brushed-metal hairlines to lay over a coloured plate (painted once).
class BrushedTexture extends StatelessWidget {
  const BrushedTexture({super.key});
  @override
  Widget build(BuildContext context) => const CachedPaint(painter: _HairlinePainter(), cacheKey: 'hairline');
}

class _HairlinePainter extends CustomPainter {
  const _HairlinePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(3);
    final p = Paint()..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 1.5) {
      p.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: rnd.nextDouble() * .045);
      final x0 = rnd.nextDouble() * size.width * .4;
      canvas.drawLine(Offset(x0, y), Offset(x0 + size.width * (.3 + rnd.nextDouble() * .7), y), p);
    }
  }

  @override
  bool shouldRepaint(_HairlinePainter old) => false;
}

/// Paints a static [painter] ONCE into a bitmap (per size / pixel ratio / [cacheKey]) and from
/// then on only blits that bitmap. Textures made of hundreds or thousands of strokes (brushed
/// metal, carpet) otherwise get replayed stroke by stroke on every frame of any animation
/// anywhere on the screen.
class CachedPaint extends StatefulWidget {
  const CachedPaint({super.key, required this.painter, required this.cacheKey});
  final CustomPainter painter;
  final Object cacheKey;
  @override
  State<CachedPaint> createState() => _CachedPaintState();
}

class _CachedPaintState extends State<CachedPaint> {
  ui.Image? _img;
  Object? _key;

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  ui.Image? _imageFor(Size size, double dpr) {
    if (!size.isFinite || size.isEmpty) return null;
    final key = (widget.cacheKey, size.width.round(), size.height.round(), dpr);
    if (key != _key || _img == null) {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(dpr);
      widget.painter.paint(canvas, size);
      final pic = rec.endRecording();
      final img = pic.toImageSync(math.max(1, (size.width * dpr).ceil()), math.max(1, (size.height * dpr).ceil()));
      pic.dispose();
      _img?.dispose();
      _img = img;
      _key = key;
    }
    return _img;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final img = _imageFor(size, dpr);
      if (img == null) return const SizedBox.shrink();
      return RepaintBoundary(
        child: RawImage(image: img, width: size.width, height: size.height, fit: BoxFit.fill, filterQuality: FilterQuality.none),
      );
    });
  }
}
