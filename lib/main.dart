import 'dart:async';

import 'package:flutter/material.dart';

import 'src/controller.dart';
import 'src/perf.dart';
import 'src/ui/home.dart';
import 'src/ui/panels.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RxThemes.load();
  await PerfLog.start();
  runApp(const RedlineApp());
}

class RedlineApp extends StatefulWidget {
  const RedlineApp({super.key});
  @override
  State<RedlineApp> createState() => _RedlineAppState();
}

class _RedlineAppState extends State<RedlineApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final Future<PedalController> _controller = _start();
  PedalController? _c;
  StreamSubscription<String>? _errors;

  Future<PedalController> _start() async {
    final started = DateTime.now();
    final c = await PedalController.create();
    // let the power-on animation play once
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _c = c;
    _errors = c.errors.listen((m) => _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 5))));
    c.start();
    return c;
  }

  @override
  void dispose() {
    _errors?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // a theme change rebuilds everything (painters read the theme when they paint)
    return ListenableBuilder(
      listenable: RxThemes.current,
      builder: (context, _) => _app(RxThemes.current.value),
    );
  }

  Widget _app(RxThemeId theme) {
    return MaterialApp(
      title: 'REDLINE FX',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scaffoldMessengerKey: _messenger,
      home: FutureBuilder<PedalController>(
        future: _controller,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('起動できませんでした\n${snap.error}'))));
          }
          final c = snap.data;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            child: c == null ? const _PowerOn(key: ValueKey('boot')) : HomePage(key: ValueKey('home-${theme.name}'), c: c),
          );
        },
      ),
    );
  }
}

/// Boot screen: the logo "powers on" with a sweeping redline.
class _PowerOn extends StatelessWidget {
  const _PowerOn({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Rx.bg,
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              Opacity(opacity: t, child: Transform.scale(scale: .9 + .1 * t, child: const Logo(size: 40))),
              const SizedBox(height: 18),
              SizedBox(
                width: 260,
                height: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: t,
                    child: Container(decoration: BoxDecoration(color: Rx.red, boxShadow: [BoxShadow(color: Rx.red.withValues(alpha: .8), blurRadius: 12)])),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
