import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orb_voice_visualizer/orb_voice_visualizer.dart';

void main() {
  group('motion', () {
    test('each state has the web version\'s motion', () {
      expect(orbMotion(OrbState.idle), const OrbMotion(speed: 0.35, displace: 0.1, glow: 0.25, react: 0.3));
      expect(orbMotion(OrbState.listening), const OrbMotion(speed: 0.9, displace: 0.16, glow: 0.45, react: 1));
      expect(orbMotion(OrbState.thinking), const OrbMotion(speed: 2.2, displace: 0.2, glow: 0.35, react: 0.2));
      expect(orbMotion(OrbState.speaking), const OrbMotion(speed: 1.2, displace: 0.14, glow: 0.55, react: 1));
    });

    test('calm slows the flow and flattens the surface', () {
      final calm = orbMotion(OrbState.thinking).calm();
      expect(calm.speed, closeTo(0.55, 1e-9));
      expect(calm.displace, closeTo(0.1, 1e-9));
      expect(calm.glow, 0.35);
      expect(calm.react, 0.2);
    });

    test('labels name the state', () {
      expect(orbLabel(OrbState.listening), 'Assistant is listening');
      expect(orbLabel(OrbState.idle), 'Assistant is idle');
    });
  });

  group('spring', () {
    test('settles on the target within a second without overshooting', () {
      var s = SpringState.rest;
      var peak = 0.0;
      for (var i = 0; i < 60; i++) {
        s = stepSpring(s, 1, 1 / 60);
        if (s.x > peak) peak = s.x;
      }
      expect(s.x, closeTo(1, 0.01));
      expect(peak, lessThan(1.01));
    });

    test('keeps its velocity when the target drops mid-flight', () {
      var s = SpringState.rest;
      for (var i = 0; i < 5; i++) {
        s = stepSpring(s, 1, 1 / 60);
      }
      expect(s.v, greaterThan(0));
      expect(stepSpring(s, 0, 1 / 60).x, greaterThan(s.x));
    });
  });

  group('params', () {
    test('lerp blends motion and colours', () {
      const a = OrbParams(OrbMotion(speed: 0, displace: 0, glow: 0, react: 0), Color(0xFF000000), Color(0xFF000000));
      const b = OrbParams(OrbMotion(speed: 2, displace: 0.2, glow: 1, react: 1), Color(0xFFFFFFFF), Color(0xFFFFFFFF));
      final mid = OrbParams.lerp(a, b, 0.5);
      expect(mid.motion.speed, 1);
      expect(mid.motion.displace, closeTo(0.1, 1e-9));
      expect(mid.color1.r, closeTo(0.5, 0.01));
      expect(OrbParams.lerp(a, b, 0).motion, a.motion);
      expect(OrbParams.lerp(a, b, 1).color2, b.color2);
    });

    test('of() picks the state\'s colours and applies calm', () {
      final p = OrbParams.of(OrbState.speaking, OrbColors.standard, calm: true);
      expect(p.color1, const Color(0xFFFF5FA2));
      expect(p.color2, const Color(0xFFFFB347));
      expect(p.motion, orbMotion(OrbState.speaking).calm());
    });
  });

  group('colours', () {
    test('all() colours every state; perState() falls back to the standard palette', () {
      const all = OrbColors.all(Color(0xFF111111), Color(0xFF222222));
      for (final state in OrbState.values) {
        expect(all.of(state), (const Color(0xFF111111), const Color(0xFF222222)));
      }
      const some = OrbColors.perState({OrbState.thinking: (Color(0xFF000000), Color(0xFFFFFFFF))});
      expect(some.of(OrbState.thinking), (const Color(0xFF000000), const Color(0xFFFFFFFF)));
      expect(some.of(OrbState.idle), OrbColors.standard.of(OrbState.idle));
      expect(OrbColors.standard.of(OrbState.idle), (const Color(0xFF4C8DFF), const Color(0xFFA06BFF)));
    });
  });

  group('helpers', () {
    test('levelFromDecibels maps the floor to 0 and full scale to 1', () {
      expect(levelFromDecibels(0), 1);
      expect(levelFromDecibels(-60), 0);
      expect(levelFromDecibels(-30), 0.5);
      expect(levelFromDecibels(-90), 0);
      expect(levelFromDecibels(6), 1);
      expect(levelFromDecibels(double.nan), 0);
      expect(levelFromDecibels(-20, floor: -40), 0.5);
    });

    test('easeInOut is symmetric', () {
      expect(easeInOut(0), 0);
      expect(easeInOut(0.5), 0.5);
      expect(easeInOut(1), 1);
      expect(easeInOut(0.25), closeTo(1 - easeInOut(0.75), 1e-9));
    });
  });

  group('widget', () {
    setUp(() => Orb.debugDisableShader = true);
    tearDown(() => Orb.debugDisableShader = false);

    Widget app(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
    );

    testWidgets('screen readers hear the state, or the label you give it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Orb(state: OrbState.listening)));
      expect(find.bySemanticsLabel('Assistant is listening'), findsOneWidget);
      await tester.pumpWidget(app(const Orb(state: OrbState.thinking)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.bySemanticsLabel('Assistant is thinking'), findsOneWidget);
      await tester.pumpWidget(app(const Orb(semanticsLabel: 'Voice assistant')));
      expect(find.bySemanticsLabel('Voice assistant'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('draws at the given size with the fallback painter', (tester) async {
      await tester.pumpWidget(app(const Orb(size: 180, level: 0.5)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byType(Orb)), const Size(180, 180));
      expect(find.descendant(of: find.byType(Orb), matching: find.byType(CustomPaint)), findsOneWidget);
    });

    testWidgets('follows a level stream and cancels it when removed', (tester) async {
      var cancelled = false;
      final levels = StreamController<double>(onCancel: () => cancelled = true);
      await tester.pumpWidget(app(Orb(state: OrbState.speaking, levelStream: levels.stream)));
      levels.add(0.8);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(app(const SizedBox()));
      expect(cancelled, isTrue);
      // Awaiting close() would wait on the cancelled listener forever under the fake clock.
      unawaited(levels.close());
    });

    testWidgets('changing state, colours and motion settings rebuilds without errors', (tester) async {
      await tester.pumpWidget(app(const Orb()));
      await tester.pumpWidget(app(const Orb(state: OrbState.speaking, colors: OrbColors.all(Color(0xFFFFFFFF), Color(0xFF000000)))));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(app(const Orb(state: OrbState.speaking), reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });
}
