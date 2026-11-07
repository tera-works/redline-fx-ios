// Head unit (LCD, instrument toggle, Bluetooth), live rack (meters, input trim, tuner,
// looper, DSP) and dialogs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller.dart';
import '../level_log.dart';
import 'controls.dart';
import 'indicators.dart';
import 'theme.dart';

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: 'REDLINE', style: TextStyle(color: Rx.red, shadows: Rx.glow(Rx.red, size * .5))),
          TextSpan(text: ' / ', style: TextStyle(color: Rx.text.withValues(alpha: .3))),
          TextSpan(text: 'FX', style: TextStyle(color: Rx.text)),
        ]),
        style: TextStyle(fontFamily: Rx.display, fontSize: size * Rx.displayScale, fontWeight: FontWeight.w800, letterSpacing: size * .06, height: 1),
      );
}

String linkText(LinkState s) => switch (s) {
      LinkState.idle => 'disconnected',
      LinkState.scanning => 'scanning...',
      LinkState.connecting => 'connecting...',
      LinkState.connected => 'connected',
      LinkState.error => 'error',
    };

Color linkColor(LinkState s) => switch (s) {
      LinkState.connected => Rx.green,
      LinkState.error => Rx.red,
      LinkState.idle => Rx.dim,
      _ => Rx.gold,
    };

/// LED that can blink (scanning / connecting).
class BlinkLed extends StatefulWidget {
  const BlinkLed({super.key, required this.color, required this.blink, this.size = 10});
  final Color color;
  final bool blink;
  final double size;
  @override
  State<BlinkLed> createState() => _BlinkLedState();
}

class _BlinkLedState extends State<BlinkLed> {
  // Discrete on/off steps from a timer: 2 repaints per second instead of a 60 fps tween.
  // (An endlessly animating widget makes Flutter re-composite the whole window every frame.)
  Timer? _timer;
  bool _on = true;

  void _sync() {
    if (widget.blink && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 550), (_) {
        if (mounted) setState(() => _on = !_on);
      });
    } else if (!widget.blink && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _on = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BlinkLed old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.blink && !_on ? .3 : 1.0;
    return RepaintBoundary(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: k),
          boxShadow: Rx.shadows([BoxShadow(color: widget.color.withValues(alpha: .7 * k), blurRadius: widget.size * .8)]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- head unit LCD
/// The pedal's "display": RIG number in 7-segment digits, RIG name, both scene tones,
/// instrument and link state. Amber for guitar, cyan for bass.
class HeadUnitDisplay extends StatelessWidget {
  const HeadUnitDisplay({super.key, required this.c, this.compact = false});
  final PedalController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lcd = Rx.lcd(c.bass);
    final lib = c.library;
    final sel = lib.data.selected;
    final sub = lib.rigSubtitle(sel);
    final name = TextStyle(fontFamily: Rx.display, fontSize: (compact ? 17 : 22) * Rx.displayScale, fontWeight: FontWeight.w800, color: lcd, letterSpacing: .5, shadows: Rx.glow(lcd, 8));
    return RepaintBoundary(
      child: LcdGlass(
      color: lcd,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 6 : 9),
      child: Row(children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RIG', style: TextStyle(fontFamily: Rx.condensed, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2, color: lcd.withValues(alpha: .6))),
          const SizedBox(height: 2),
          _Rolling(
            keyValue: '$sel${c.bass}',
            child: SevenSeg(sel.toString().padLeft(2, '0'), color: lcd, height: compact ? 30 : 44),
          ),
        ]),
        SizedBox(width: compact ? 10 : 18),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Rolling(keyValue: '${lib.rigName(sel)}${c.bass}', child: Text(lib.rigName(sel), maxLines: 1, overflow: TextOverflow.ellipsis, style: name)),
            if (sub.isNotEmpty && !compact)
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: lcd.withValues(alpha: .55), letterSpacing: .5)),
            if (!compact) ...[
              const SizedBox(height: 5),
              Row(children: [
                Expanded(child: _SceneLine(label: 'OFF', name: c.active[0].name, editing: c.side == 0, color: lcd)),
                const SizedBox(width: 12),
                Expanded(child: _SceneLine(label: 'ON', name: c.active[1].name, editing: c.side == 1, color: lcd)),
              ]),
            ],
          ]),
        ),
        SizedBox(width: compact ? 8 : 14),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          AnimatedSwitcher(
            duration: Duration.zero,
            child: Text(c.bass ? 'BASS' : 'GUITAR',
                key: ValueKey(c.bass), style: TextStyle(fontFamily: Rx.condensed, fontSize: compact ? 10 : 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: lcd, shadows: Rx.glow(lcd, 6))),
          ),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bluetooth, size: 13, color: c.connected ? lcd : lcd.withValues(alpha: .3)),
            if (!compact)
              Text(c.dspLoad == null ? '' : ' DSP ${c.dspLoad!.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10.5, color: lcd.withValues(alpha: .7), fontFeatures: Rx.tabular)),
          ]),
        ]),
      ]),
      ),
    );
  }
}

class _SceneLine extends StatelessWidget {
  const _SceneLine({required this.label, required this.name, required this.editing, required this.color});
  final String label, name;
  final bool editing;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 170), curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: editing ? color : Colors.transparent, borderRadius: BorderRadius.circular(3), border: Border.all(color: color.withValues(alpha: .6))),
          child: Text(label, style: TextStyle(fontFamily: Rx.condensed, fontSize: 9.5, fontWeight: FontWeight.w800, color: editing ? Colors.black : color, letterSpacing: 1)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color.withValues(alpha: editing ? .95 : .6)))),
      ]);
}

/// Rolls its child vertically when [keyValue] changes (like a counter).
class _Rolling extends StatelessWidget {
  const _Rolling({required this.keyValue, required this.child});
  final String keyValue;
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          // only the new value is drawn (no overlapping fade)
          layoutBuilder: (current, previous) => Align(alignment: Alignment.centerLeft, child: current),
          transitionBuilder: (child, a) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, .5), end: Offset.zero).animate(a), child: child),
          child: KeyedSubtree(key: ValueKey(keyValue), child: child),
        ),
      );
}

// ---------------------------------------------------------------- instrument toggle
/// GUITAR ◀ bat-handle toggle ▶ BASS. Swaps the whole library (tones + RIGs).
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.c, this.compact = false});
  final PedalController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bass = c.bass;
    TextStyle st(bool on, Color col) => TextStyle(fontFamily: Rx.condensed, 
          fontSize: compact ? 10.5 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: on ? col : Rx.faint,
          shadows: on ? Rx.glow(col, 6) : null,
        );
    return Tooltip(
      message: 'ギター／ベースを切り替え（音色とRIGのライブラリごと入れ替わります）',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: c.busy ? null : c.switchInstrument,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic, style: st(!bass, Rx.light ? Rx.text : Rx.lcd(false)), child: const Text('GUITAR')),
            const SizedBox(width: 8),
            Container(
              width: compact ? 40 : 50,
              height: compact ? 22 : 26,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black,
                border: Border.all(color: Rx.line),
                boxShadow: const [BoxShadow(color: Color(0x22FFFFFF), offset: Offset(0, 1))],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: bass ? Alignment.centerRight : Alignment.centerLeft,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFF4F5F7), Color(0xFF6A7078)]),
                      boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic, style: st(bass, Rx.light ? Rx.text : Rx.lcd(true)), child: const Text('BASS')),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Bluetooth
/// Device list + 接続 / 切断 + state line with a status LED.
class BluetoothBox extends StatelessWidget {
  const BluetoothBox({super.key, required this.c, this.expand = false});
  final PedalController c;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final state = c.linkState;
    final linked = c.connected;
    final dropdown = DropdownButton<String>(
      value: c.devices.any((d) => d.id == c.selectedDevice) ? c.selectedDevice : null,
      hint: Text('本体を検索中', style: TextStyle(color: Rx.dim, fontSize: 13)),
      isExpanded: true,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: Rx.raised,
      items: [
        for (final d in c.devices) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: linked || c.busy
          ? null
          : (id) {
              if (id != null) c.selectDevice(id);
            },
    );
    final button = linked
        ? OutlinedButton(onPressed: c.busy ? null : c.disconnect, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)), child: const Text('切断'))
        : FilledButton(onPressed: c.busy || c.selectedDevice == null ? null : c.connect, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), child: const Text('接続'));
    final busyLink = state == LinkState.scanning || state == LinkState.connecting;
    return Plate(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: SizedBox(
        width: expand ? double.infinity : 330,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.bluetooth, size: 16, color: Rx.dim),
            const SizedBox(width: 6),
            Expanded(child: Well(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: dropdown)),
            const SizedBox(width: 8),
            button,
          ]),
          const SizedBox(height: 6),
          Row(children: [
            BlinkLed(color: linkColor(state), blink: busyLink, size: 8),
            const SizedBox(width: 8),
            Text(linkText(state), style: TextStyle(color: linkColor(state), fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: .5)),
            const Spacer(),
            if (state == LinkState.error || (state == LinkState.scanning && c.devices.isEmpty))
              TextButton(onPressed: c.busy ? null : c.rescan, style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('再検索')),
          ]),
          if (state == LinkState.error && c.linkError.isNotEmpty)
            Text(c.linkError, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11.5)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- live rack
/// Rack unit with the live tools. [vertical] stacks the sections (phone).
class LiveRack extends StatelessWidget {
  const LiveRack({super.key, required this.c, this.vertical = false, this.meters = true});
  final PedalController c;
  final bool vertical;
  final bool meters; // false when the layout shows the levels elsewhere (console VU bridge)

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (meters) _MetersSection(c: c, width: vertical ? double.infinity : 250),
      _Section(title: 'INPUT', child: TrimControl(c: c)),
      _Section(title: 'TUNER', child: _TunerButton(c: c)),
      _Section(title: 'LOOPER', child: _Looper(c: c)),
      _Section(
        title: 'SYSTEM',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LcdReadout(c.dspLoad == null ? 'DSP --' : 'DSP ${c.dspLoad!.toStringAsFixed(1)}%', color: Rx.lcd(c.bass), width: 92),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => showLevelLog(context, c),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
            child: Text('LOG', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12)),
          ),
        ]),
      ),
    ];
    if (vertical) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in sections) Padding(padding: const EdgeInsets.only(bottom: 10), child: Plate(child: s)),
      ]);
    }
    return Plate(
      screws: true,
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) Container(width: 1, height: 60, margin: const EdgeInsets.symmetric(horizontal: 16), color: Colors.black.withValues(alpha: .6)),
              RepaintBoundary(child: sections[i]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(title, size: 10),
        const SizedBox(height: 6),
        child,
      ]);
}

class _MetersSection extends StatelessWidget {
  const _MetersSection({required this.c, required this.width});
  final PedalController c;
  final double width;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c.meters,
        builder: (context, _) {
          final w = width.isFinite ? width : 320.0;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LedMeter(label: 'IN', meter: c.meters.input, width: w),
            const SizedBox(height: 3),
            LedMeter(label: 'OUT', meter: c.meters.output, width: w),
            const SizedBox(height: 3),
            SizedBox(width: w, child: _SessionSummary(c: c)),
          ]);
        },
      );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final s = c.meters.session;
    String db(double v) => toDb(v).toStringAsFixed(1);
    final base = TextStyle(fontSize: 11, color: Rx.dim, fontFeatures: Rx.tabular);
    if (s == null) {
      final e = c.levelLog.entries.isEmpty ? null : c.levelLog.entries.last;
      if (e == null) return Text(' ', style: base);
      return Text('直近 ${e.endText}  IN 最大 ${e.inMaxDb.toStringAsFixed(1)} / 平均 ${e.inAvgDb.toStringAsFixed(1)}', overflow: TextOverflow.ellipsis, style: base);
    }
    final clips = s.inClips + s.outClips;
    final clip = clips > 0 ? '  クリップ $clips' : '';
    final text = s.active ? '● 演奏中  IN 最大 ${db(s.inMax)} / 平均 ${db(s.inAvg)}$clip' : '直近  IN ${db(s.inMax)} / ${db(s.inAvg)}  OUT ${db(s.outMax)}$clip';
    return Text(text, overflow: TextOverflow.ellipsis, style: base.copyWith(color: clips > 0 ? Rx.red : (s.active ? Rx.green : Rx.dim)));
  }
}

class _TunerButton extends StatelessWidget {
  const _TunerButton({required this.c});
  final PedalController c;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: c.connected && !c.busy ? () => showTuner(context, c) : null,
        icon: const Icon(Icons.graphic_eq, size: 18),
        label: Text('TUNE', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      );
}

class _Looper extends StatelessWidget {
  const _Looper({required this.c});
  final PedalController c;
  @override
  Widget build(BuildContext context) {
    final ok = c.connected;
    final live = c.live;
    final lcd = Rx.lcd(c.bass);
    final stateColor = live == null ? lcd.withValues(alpha: .5) : (live.recording ? Rx.red : (live.playing ? Rx.green : lcd));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: 'ONの間はフットスイッチでルーパーを操作（音色は固定）\n踏む：録音 → 再生 → 重ね録り → 再生…\n2回続けて踏む：停止　停止中に2回：消去',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          JewelLed(on: c.looperOn, size: 9),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: FilledButton(
              onPressed: ok && !c.busy ? c.toggleLooper : null,
              style: FilledButton.styleFrom(
                backgroundColor: c.looperOn ? Rx.red : Rx.raised,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(color: c.looperOn ? Rx.red : Rx.line),
              ),
              child: Text(c.looperOn ? 'ON' : 'OFF', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 10),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        LcdReadout(ok && live != null ? live.describe() : '—', color: stateColor, width: 170, active: live != null && live.recording),
        const SizedBox(height: 5),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _MiniButton(icon: Icons.stop, tip: 'ループを止める（録音は残ります）', onTap: ok && live != null && live.loopState != 0 && live.loopState != 4 && !c.busy ? () => c.loopAction(2) : null),
          const SizedBox(width: 6),
          _MiniButton(icon: Icons.delete_outline, tip: 'ループを消去', onTap: ok && live != null && live.loopState != 0 && !c.busy ? () => c.loopAction(3) : null),
        ]),
      ]),
      const SizedBox(width: 10),
      Tooltip(
        message: 'ループの再生音量 ${c.loopLevel}%',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IgnorePointer(
            ignoring: !ok,
            child: Opacity(
              opacity: ok ? 1 : .45,
              child: Knob(
                value: c.loopLevel / 200,
                size: 46,
                accent: lcd,
                onChanged: (v) {
                  c.setLoopLevel((v * 200).round());
                  c.endLoopLevelDrag();
                },
              ),
            ),
          ),
          Text('${c.loopLevel}%', style: TextStyle(fontSize: 10.5, color: lcd, fontFeatures: Rx.tabular)),
        ]),
      ),
    ]);
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: SizedBox(
          width: 40,
          height: 28,
          child: OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), child: Icon(icon, size: 16)),
        ),
      );
}

/// INPUT trim of the current instrument, with AUTO from the level log.
class TrimControl extends StatelessWidget {
  const TrimControl({super.key, required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    final trim = c.inputTrim;
    final ok = c.connected && trim != null;
    final sug = c.trimSuggestion;
    final lcd = Rx.lcd(c.bass);
    String fmt(int v) => '${v > 0 ? '+' : ''}$v dB';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _MiniButton(icon: Icons.remove, tip: '入力 -1 dB', onTap: ok ? () => c.setInputTrim(trim - 1) : null),
      const SizedBox(width: 6),
      Tooltip(
        message: '${c.bass ? 'ベース' : 'ギター'}の入力レベル補正（本体に保存）。\n音色は IN 平均 ${c.bass ? '-26' : '-28'} dBFS 前後で作ってあります',
        child: LcdReadout(trim == null ? '-- dB' : fmt(trim), color: lcd, width: 70, fontSize: 14),
      ),
      const SizedBox(width: 6),
      _MiniButton(icon: Icons.add, tip: '入力 +1 dB', onTap: ok ? () => c.setInputTrim(trim + 1) : null),
      const SizedBox(width: 6),
      Tooltip(
        message: sug == null
            ? 'レベルログがまだ足りません（${c.bass ? 'ベース' : 'ギター'}で合計20秒以上弾くと推定できます）'
            : '直近 ${sug.sessions} 回の IN 平均 ${sug.avgDb.toStringAsFixed(1)} dBFS から推定: ${fmt(sug.db)}',
        child: TextButton(
          onPressed: ok && sug != null && sug.db != trim ? () => c.setInputTrim(sug.db) : null,
          child: Text(sug == null ? 'AUTO' : 'AUTO ${fmt(sug.db)}', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1)),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- tuner
Future<void> showTuner(BuildContext context, PedalController c) async {
  await c.openTuner();
  if (!c.tunerOpen || !context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .7),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => _TunerDialog(c: c),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween<double>(begin: .92, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
    ),
  );
  await c.closeTuner();
}

class _TunerDialog extends StatefulWidget {
  const _TunerDialog({required this.c});
  final PedalController c;
  @override
  State<_TunerDialog> createState() => _TunerDialogState();
}

class _TunerDialogState extends State<_TunerDialog> with SingleTickerProviderStateMixin {
  bool _closing = false;
  late final Ticker _ticker;
  double _phase = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      final cents = widget.c.tunerCents;
      if (cents != null && cents.abs() >= 1) {
        setState(() => _phase += dt * cents.clamp(-50.0, 50.0).toDouble() * .04);
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Pops this dialog once, and only while it is the top route.
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        final c = widget.c;
        if (!c.tunerOpen && !_closing) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _close());
        }
        final live = c.tunerLive;
        final cents = c.tunerCents;
        final reading = live != null && cents != null ? analyseNote(live.hz, a4: c.tunerA4) : null;
        final color = cents == null ? Rx.faint : (cents.abs() < 2 ? Rx.green : (cents.abs() < 10 ? Rx.gold : Rx.red));
        final lcd = Rx.lcd(c.bass);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Plate(
                screws: true,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    SectionTitle('TUNER', size: 14, color: Rx.text),
                    const SizedBox(width: 10),
                    const SectionTitle('OUTPUT MUTED', size: 10),
                    const Spacer(),
                    JewelLed(on: cents != null && cents.abs() < 2, color: Rx.green, size: 12),
                  ]),
                  const SizedBox(height: 10),
                  LcdGlass(
                    color: lcd,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Column(children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
                        transitionBuilder: (child, a) => ScaleTransition(scale: Tween<double>(begin: .92, end: 1).animate(a), child: child),
                        child: Text(reading?.note ?? '—',
                            key: ValueKey(reading?.note ?? '-'),
                            style: TextStyle(fontFamily: Rx.condensed, fontSize: 76, fontWeight: FontWeight.w800, color: color, height: 1.05, shadows: Rx.glow(color, 16))),
                      ),
                      AspectRatio(
                        aspectRatio: 2.3,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: cents ?? 0),
                          duration: const Duration(milliseconds: 270), curve: Curves.easeOutCubic,
                          builder: (context, v, _) => CustomPaint(painter: StrobePainter(phase: _phase, cents: cents == null ? null : v, color: color == Rx.faint ? lcd : color)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reading == null ? ' ' : '${reading.note}${reading.octave}   ${cents! >= 0 ? '+' : ''}${cents.toStringAsFixed(1)} cent   ${live!.hz.toStringAsFixed(2)} Hz',
                        style: TextStyle(fontSize: 15, color: lcd, fontFeatures: Rx.tabular, shadows: Rx.glow(lcd, 6)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      color: Rx.dim,
                      tooltip: '基準音を下げる',
                      onPressed: c.tunerA4 > PedalController.tunerA4Min ? () => c.setTunerA4(c.tunerA4 - 1) : null,
                    ),
                    GestureDetector(
                      onDoubleTap: () => c.setTunerA4(PedalController.tunerA4Default), // same reset gesture as the knobs
                      child: Text('A4 = ${c.tunerA4.toStringAsFixed(0)} Hz',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: Rx.tabular, color: c.tunerA4 == PedalController.tunerA4Default ? Rx.dim : Rx.gold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      color: Rx.dim,
                      tooltip: '基準音を上げる',
                      onPressed: c.tunerA4 < PedalController.tunerA4Max ? () => c.setTunerA4(c.tunerA4 + 1) : null,
                    ),
                    const Spacer(),
                    TextButton(onPressed: _close, child: const Text('閉じる')),
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- dialogs
Future<void> showLevelLog(BuildContext context, PedalController c) => showDialog<void>(
      context: context,
      builder: (context) {
        final entries = c.levelLog.entries.reversed.toList();
        return Dialog(
          backgroundColor: Rx.panel,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('LEVEL LOG', size: 16),
                const SizedBox(height: 6),
                Text('演奏ごとの入出力レベル（新しい順）。IN 平均が -30〜-18 dBFS なら、コンプ・歪み・オートワウの設定が想定どおりに効きます。',
                    style: TextStyle(fontSize: 12.5, color: Rx.dim)),
                const SizedBox(height: 10),
                Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text('まだ記録がありません（本体に接続して2秒以上弾くと記録されます）', style: TextStyle(color: Rx.dim)))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _LogRow(entries[i]),
                        ),
                ),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる'))),
              ]),
            ),
          ),
        );
      },
    );

class _LogRow extends StatelessWidget {
  const _LogRow(this.e);
  final LevelEntry e;
  @override
  Widget build(BuildContext context) {
    final color = e.clipped ? Rx.red : Rx.text;
    TextStyle st([Color? c]) => TextStyle(fontSize: 13, color: c ?? color, fontFeatures: Rx.tabular);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Wrap(spacing: 16, runSpacing: 2, children: [
        Text('${e.endText}  ${e.durationText}', style: st()),
        Text('IN 最大 ${e.inMaxDb.toStringAsFixed(1)}  平均 ${e.inAvgDb.toStringAsFixed(1)}', style: st()),
        Text('OUT 最大 ${e.outMaxDb.toStringAsFixed(1)} dBFS', style: st()),
        if (e.clipped) Text('クリップ IN ${e.inClips} / OUT ${e.outClips}', style: st(Rx.red)),
        Text('${e.mode == 'bass' ? 'BASS' : 'GUITAR'}  ${e.rig}', style: st(Rx.dim)),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Rx.panel,
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('OK')),
      ],
    ),
  );
  return r ?? false;
}

/// 音色の管理: overwrite / reset the selected tone slot.
Future<void> showToneManager(BuildContext context, PedalController c) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Rx.panel,
      builder: (context) {
        final i = c.selectedTone;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('音色プリセットの管理', size: 15),
              const SizedBox(height: 4),
              Text('${i.toString().padLeft(2, '0')}  ${c.library.data.tones[i].name}', style: TextStyle(color: Rx.dim)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('音色プリセットに上書き'),
                subtitle: Text('編集中の ${c.side == 0 ? 'OFF' : 'ON'} 音色をこのスロットに保存'),
                onTap: () {
                  c.overwriteTone();
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('音色を初期化'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  if (await confirm(context, '選択音色を初期化しますか？')) c.resetTone();
                  nav.pop();
                },
              ),
            ]),
          ),
        );
      },
    );

/// テーマ選択: four looks, same layout. Applied at once and remembered.
Future<void> showThemePicker(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) {
        // AlertDialog measures its content's intrinsic width, so size from the screen, not a LayoutBuilder.
        // Dialog inset 40 + content padding 20 on each side; one column on phones.
        final width = math.min(560.0, MediaQuery.sizeOf(context).width - 120);
        final cols = width < 420 ? 1 : 2;
        final cardW = (width - (cols - 1) * 12) / cols;
        return AlertDialog(
          backgroundColor: Rx.panel,
          scrollable: true,
          title: Text('テーマ', style: TextStyle(fontFamily: Rx.condensed, fontWeight: FontWeight.w800, letterSpacing: 2, color: Rx.text)),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          content: SizedBox(
            width: width,
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in RxPalettes.all)
                SizedBox(
                  width: cardW,
                  height: 104,
                  child: _ThemeCard(
                    p: p,
                    selected: p.id == RxThemes.current.value,
                    onTap: () {
                      Navigator.of(context).pop();
                      RxThemes.set(p.id);
                    },
                  ),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる'))],
        );
      },
    );

/// A small preview of a theme: its backdrop, a panel, an enclosure, the accent and the display.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.p, required this.selected, required this.onTap});
  final RxPalette p;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.bgTop, p.bg]),
            border: Border.all(color: selected ? Rx.gold : Rx.line, width: selected ? 2.5 : 1),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(p.pedal == PedalStyle.anodized ? 8 : (p.pedal == PedalStyle.stomp ? 6 : 3)),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(p.blocks[1], Colors.white, .15)!, p.blocks[1]]),
                border: Border.all(color: Colors.black54),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: p.red, boxShadow: [BoxShadow(color: p.red, blurRadius: 6)])),
                Text('DRIVE', style: TextStyle(fontFamily: p.condensed, fontSize: 11, fontWeight: FontWeight.w800, color: p.onBlock)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(p.name, maxLines: 1, style: TextStyle(fontFamily: p.condensed, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.text))),
                const SizedBox(height: 2),
                Flexible(child: Text(p.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.dim))),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF0C0B09), borderRadius: BorderRadius.circular(3)),
                  child: Text('RIG 02', style: TextStyle(fontFamily: p.mono, fontSize: 12, color: p.lcdGuitar)),
                ),
              ]),
            ),
            if (selected) Icon(Icons.check_circle, color: Rx.gold, size: 20),
          ]),
        ),
      ),
    );
  }
}

enum MenuAction { theme, exportFile, importFile, resetAll }

/// Settings file menu (書き出し / 読み込み / 全設定を初期化).
class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key, required this.c});
  final PedalController c;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuAction>(
      tooltip: 'テーマ・設定ファイル',
      icon: const Icon(Icons.more_vert),
      color: Rx.raised,
      onSelected: (a) => _run(context, a),
      itemBuilder: (_) => const [
        PopupMenuItem(value: MenuAction.theme, child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('テーマ'))),
        PopupMenuDivider(),
        PopupMenuItem(value: MenuAction.exportFile, child: ListTile(leading: Icon(Icons.upload_file), title: Text('書き出し'))),
        PopupMenuItem(value: MenuAction.importFile, child: ListTile(leading: Icon(Icons.file_open), title: Text('読み込み'))),
        PopupMenuItem(value: MenuAction.resetAll, child: ListTile(leading: Icon(Icons.restart_alt), title: Text('全設定を初期化'))),
      ],
    );
  }

  Future<void> _run(BuildContext context, MenuAction a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (a) {
        case MenuAction.theme:
          if (context.mounted) await showThemePicker(context);
        case MenuAction.exportFile:
          final bytes = utf8.encode(c.exportJson());
          final path = await FilePicker.saveFile(
            dialogTitle: '設定の書き出し',
            fileName: 'Redline-FX-settings.json',
            type: FileType.custom,
            allowedExtensions: const ['json'],
            bytes: bytes,
          );
          if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) await File(path).writeAsBytes(bytes);
        case MenuAction.importFile:
          final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
          final f = r == null || r.files.isEmpty ? null : r.files.single;
          if (f == null) return;
          final data = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
          if (data == null) return;
          await c.importJson(utf8.decode(data));
        case MenuAction.resetAll:
          if (!context.mounted) return;
          if (await confirm(context, 'アプリの音色と組み合わせを初期化します（ギター・ベースとも）。本体は変更しません。')) await c.resetLibrary();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
