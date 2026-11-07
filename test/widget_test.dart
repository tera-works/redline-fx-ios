// Renders the custom controls and displays (no plugins needed).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redline_fx/src/level_log.dart';
import 'package:redline_fx/src/ui/controls.dart';
import 'package:redline_fx/src/ui/editor.dart';
import 'package:redline_fx/src/ui/indicators.dart';
import 'package:redline_fx/src/ui/panels.dart';
import 'package:redline_fx/src/ui/theme.dart';

void main() {
  testWidgets('controls render and respond', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var knob = .5, fader = .2;
    var on = false;
    var choice = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => Wrap(children: [
            Knob(value: knob, onChanged: (v) => set(() => knob = v)),
            Fader(value: fader, onChanged: (v) => set(() => fader = v)),
            StompSwitch(on: on, onChanged: (v) => set(() => on = v)),
            RotarySelector(choices: const ['OD', 'DIST', 'FUZZ', 'METAL'], index: choice, onChanged: (i) => set(() => choice = i)),
            const FootswitchView(pressed: true),
            LedMeter(label: 'IN', meter: MeterBallistics()..push(.5, DateTime.now())),
            SevenSeg('09', color: Rx.amber),
            SizedBox(width: 300, child: LcdGlass(color: Rx.amber, child: Text('RIG'))),
            LcdReadout('+6 dB'),
            JewelLed(on: true),
          ]),
        ),
      ),
    ));
    await tester.drag(find.byType(Knob), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 600));
    expect(knob, closeTo(.75, .1));
    await tester.tap(find.byType(StompSwitch));
    await tester.pump(const Duration(milliseconds: 600));
    expect(on, isTrue);
    await tester.tap(find.text('METAL'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(choice, 3);
  });

  testWidgets('every theme paints the controls', (tester) async {
    for (final p in RxPalettes.all) {
      Rx.t = p;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Stack(children: [
            const Positioned.fill(child: BrushedBackground()),
            Wrap(children: [
              Knob(value: .6, onChanged: (_) {}),
              Knob(value: .3, accent: Rx.dim, onChanged: (_) {}),
              Fader(value: .4, onChanged: (_) {}),
              const Plate(child: SectionTitle('RIG PRESETS')),
              LcdReadout('6.8'),
            ]),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: p.name);
    }
    Rx.t = RxPalettes.studio;
  });

  testWidgets('theme picker fits a phone and a desktop', (tester) async {
    for (final size in const [Size(390, 844), Size(1400, 1000)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => showThemePicker(context), child: const Text('open')))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      for (final p in RxPalettes.all) {
        expect(find.text(p.name), findsOneWidget);
      }
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
    }
    tester.view.reset();
  });

  testWidgets('seven-way selector fits the effect cell', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 218,
            child: RotarySelector(choices: const ['FLANGER', 'CHORUS', 'PHASER', 'TREMOLO', 'UNI-VIBE', 'ROTARY', 'RING MOD'], index: 6, onChanged: (_) {}),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  test('knob sensitivity / faceplate layout', () {
    expect(knobDragValue(.5, 120, false), 1);
    expect(knobDragValue(.5, -240, false), 0);
    expect(knobDragValue(.5, 120, true), .625);
    // 9 controls on a wide area -> one row; on a phone -> several rows
    expect(bestColumns(9, const Size(1400, 420)), 9);
    expect(bestColumns(9, const Size(380, 560)), lessThan(5));
  });
}
