/// Orb — a voice agent visualiser. MIT © 2026 Yagnik Barasiya.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// What the assistant is doing.
enum OrbState { idle, listening, thinking, speaking }

/// How the orb's surface moves in one state.
@immutable
class OrbMotion {
  const OrbMotion({required this.speed, required this.displace, required this.glow, required this.react});

  /// How fast the surface noise flows.
  final double speed;

  /// How deep the noise cuts into the sphere.
  final double displace;

  /// Strength of the halo around the sphere.
  final double glow;

  /// How much the audio level moves the surface, 0–1.
  final double react;

  /// Slower and shallower, for reduced motion.
  OrbMotion calm() => OrbMotion(speed: speed * 0.25, displace: displace * 0.5, glow: glow, react: react);

  static OrbMotion lerp(OrbMotion a, OrbMotion b, double t) => OrbMotion(
    speed: ui.lerpDouble(a.speed, b.speed, t)!,
    displace: ui.lerpDouble(a.displace, b.displace, t)!,
    glow: ui.lerpDouble(a.glow, b.glow, t)!,
    react: ui.lerpDouble(a.react, b.react, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is OrbMotion && other.speed == speed && other.displace == displace && other.glow == glow && other.react == react;

  @override
  int get hashCode => Object.hash(speed, displace, glow, react);

  @override
  String toString() => 'OrbMotion(speed: $speed, displace: $displace, glow: $glow, react: $react)';
}

/// The motion for [state]; the same values as the web version.
OrbMotion orbMotion(OrbState state) => switch (state) {
  OrbState.idle => const OrbMotion(speed: 0.35, displace: 0.1, glow: 0.25, react: 0.3),
  OrbState.listening => const OrbMotion(speed: 0.9, displace: 0.16, glow: 0.45, react: 1),
  OrbState.thinking => const OrbMotion(speed: 2.2, displace: 0.2, glow: 0.35, react: 0.2),
  OrbState.speaking => const OrbMotion(speed: 1.2, displace: 0.14, glow: 0.55, react: 1),
};

/// What screen readers hear for [state].
String orbLabel(OrbState state) => 'Assistant is ${state.name}';

/// The orb's two colours, for every state or per state.
@immutable
class OrbColors {
  /// The same two colours in every state.
  const OrbColors.all(Color a, Color b) : _a = a, _b = b, _byState = null;

  /// Colours per state; states you leave out use [standard].
  const OrbColors.perState(Map<OrbState, (Color, Color)> colors) : _a = null, _b = null, _byState = colors;

  /// Blue at rest, blue-green listening, violet-pink thinking, pink-amber speaking.
  static const standard = OrbColors.perState({
    OrbState.idle: (Color(0xFF4C8DFF), Color(0xFFA06BFF)),
    OrbState.listening: (Color(0xFF2E8CFF), Color(0xFF2FD3A7)),
    OrbState.thinking: (Color(0xFFA06BFF), Color(0xFFFF5FA2)),
    OrbState.speaking: (Color(0xFFFF5FA2), Color(0xFFFFB347)),
  });

  final Color? _a;
  final Color? _b;
  final Map<OrbState, (Color, Color)>? _byState;

  (Color, Color) of(OrbState state) {
    final a = _a;
    final b = _b;
    if (a != null && b != null) return (a, b);
    return _byState?[state] ?? standard._byState![state]!;
  }
}

/// Everything the painter needs for one frame, blended between states.
@immutable
class OrbParams {
  const OrbParams(this.motion, this.color1, this.color2);

  factory OrbParams.of(OrbState state, OrbColors colors, {bool calm = false}) {
    final motion = orbMotion(state);
    final (a, b) = colors.of(state);
    return OrbParams(calm ? motion.calm() : motion, a, b);
  }

  final OrbMotion motion;
  final Color color1;
  final Color color2;

  static OrbParams lerp(OrbParams a, OrbParams b, double t) => OrbParams(
    OrbMotion.lerp(a.motion, b.motion, t),
    Color.lerp(a.color1, b.color1, t)!,
    Color.lerp(a.color2, b.color2, t)!,
  );
}

/// Position and velocity of a spring.
@immutable
class SpringState {
  const SpringState(this.x, this.v);

  static const rest = SpringState(0, 0);

  final double x;
  final double v;
}

/// One step of a damped spring; critically damped by default (damping ≈ 2√stiffness).
SpringState stepSpring(SpringState s, double target, double dt, {double stiffness = 170, double damping = 26}) {
  final v = s.v + (stiffness * (target - s.x) - damping * s.v) * dt;
  return SpringState(s.x + v * dt, v);
}

/// Loudness 0–1 from dBFS, as most audio plugins report it. [floor] is silence.
double levelFromDecibels(double db, {double floor = -60}) {
  if (db.isNaN) return 0;
  return ((db - floor) / -floor).clamp(0.0, 1.0);
}

double easeInOut(double t) => t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) * (-2 * t + 2)) / 2;

/// A voice agent orb.
///
/// ```dart
/// Orb(
///   state: OrbState.listening,
///   levelStream: recorder.onAmplitudeChanged(const Duration(milliseconds: 50))
///       .map((a) => levelFromDecibels(a.current)),
/// )
/// ```
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    this.state = OrbState.idle,
    this.level,
    this.levelStream,
    this.colors = OrbColors.standard,
    this.size = 240,
    this.semanticsLabel,
  });

  /// What the assistant is doing. Changes blend over 400 ms.
  final OrbState state;

  /// Loudness 0–1 from your audio source. Ignored while [levelStream] has sent a value.
  final double? level;

  /// Loudness 0–1 as a stream, for example from a recorder's amplitude callback.
  final Stream<double>? levelStream;

  /// The orb's colours.
  final OrbColors colors;

  /// Width and height.
  final double size;

  /// What screen readers hear. Defaults to `Assistant is listening` and so on, from [state].
  final String? semanticsLabel;

  /// Skips loading the shader so tests exercise the fallback painter.
  @visibleForTesting
  static bool debugDisableShader = false;

  @override
  State<Orb> createState() => _OrbWidgetState();
}

class _OrbWidgetState extends State<Orb> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram?>? _program;

  /// Loaded once per app. Inside this package's own tests the shader is at the
  /// root asset path; in apps it is namespaced under packages/.
  static Future<ui.FragmentProgram?> _loadProgram() => _program ??= () async {
    for (final key in const ['packages/orb_voice_visualizer/shaders/orb.frag', 'shaders/orb.frag']) {
      try {
        return await ui.FragmentProgram.fromAsset(key);
      } catch (_) {
        // Try the next location; null means "use the painter".
      }
    }
    return null;
  }();

  late final _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  ui.FragmentShader? _shader;
  StreamSubscription<double>? _subscription;
  double? _streamLevel;

  bool _calm = false;
  late OrbParams _params;
  late OrbParams _from;
  double _clock = 0;
  double _blendAt = -1;
  Duration _last = Duration.zero;
  SpringState _level = SpringState.rest;
  double _phase = 0;

  double get amp => _level.x < 0 ? 0 : _level.x;
  OrbParams get params => _params;
  double get phase => _phase;

  @override
  void initState() {
    super.initState();
    _params = OrbParams.of(widget.state, widget.colors);
    _from = _params;
    _subscribe();
    if (!Orb.debugDisableShader) {
      _loadProgram().then((program) {
        if (!mounted || program == null) return;
        setState(() => _shader = program.fragmentShader());
      });
    }
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (calm != _calm) {
      _calm = calm;
      _blend();
    }
  }

  @override
  void didUpdateWidget(Orb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state || oldWidget.colors.of(widget.state) != widget.colors.of(widget.state)) _blend();
    if (oldWidget.levelStream != widget.levelStream) _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _streamLevel = null;
    _subscription = widget.levelStream?.listen((level) => _streamLevel = level);
  }

  void _blend() {
    _from = _params;
    _blendAt = _clock;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _clock += dt;
    final target = OrbParams.of(widget.state, widget.colors, calm: _calm);
    final k = _blendAt < 0 ? 1.0 : easeInOut(((_clock - _blendAt) / 0.4).clamp(0.0, 1.0));
    _params = OrbParams.lerp(_from, target, k);
    final raw = (_streamLevel ?? widget.level ?? 0).clamp(0.0, 1.0);
    _level = stepSpring(_level, raw * _params.motion.react, dt);
    _phase += dt * _params.motion.speed;
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _subscription?.cancel();
    _shader?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.semanticsLabel ?? orbLabel(widget.state),
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(child: CustomPaint(painter: _OrbPainter(this, _shader))),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.orb, this.shader) : super(repaint: orb._frame);

  final _OrbWidgetState orb;
  final ui.FragmentShader? shader;

  @override
  void paint(Canvas canvas, Size size) {
    final p = orb.params;
    final amp = orb.amp;
    final s = shader;
    if (s != null) {
      s
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, orb.phase)
        ..setFloat(3, amp)
        ..setFloat(4, p.motion.displace)
        ..setFloat(5, p.motion.glow)
        ..setFloat(6, p.color1.r)
        ..setFloat(7, p.color1.g)
        ..setFloat(8, p.color1.b)
        ..setFloat(9, p.color2.r)
        ..setFloat(10, p.color2.g)
        ..setFloat(11, p.color2.b);
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
      return;
    }

    // Fallback while the shader loads, or where shaders are unavailable.
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.3 * (1 + amp * 0.12);
    canvas.drawCircle(
      center,
      radius * 1.05,
      Paint()
        ..color = p.color1.withValues(alpha: (p.motion.glow * 0.6 + amp * 0.5).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35),
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [Color.lerp(p.color2, const Color(0xFFFFFFFF), 0.35)!, p.color2, p.color1],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.04
        ..color = const Color(0x40FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => oldDelegate.shader != shader;
}
