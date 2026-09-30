import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orb_voice_visualizer/orb_voice_visualizer.dart';

import 'controls.dart';

void main() => runApp(const OrbDemo());

const _bg = Color(0xFF050505);
const _panel = Color(0xFF0E0E10);
const _line = Color(0x1AFFFFFF);
const _muted = Color(0xFFA1A1AA);
const _accent = Color(0xFFD9F99D);

class OrbDemo extends StatelessWidget {
  const OrbDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orb — voice agent orb for Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _panel),
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> with SingleTickerProviderStateMixin {
  static const _palettes = <String, OrbColors>{
    'Per state': OrbColors.standard,
    'Sunset': OrbColors.all(Color(0xFFFF5F6D), Color(0xFFFFC371)),
    'Mint': OrbColors.all(Color(0xFF2FD3A7), Color(0xFF4C8DFF)),
    'Mono': OrbColors.all(Color(0xFFD4D4D8), Color(0xFF52525B)),
  };
  static const _swatches = <String, List<Color>>{
    'Per state': [Color(0xFF4C8DFF), Color(0xFF2FD3A7), Color(0xFFFF5FA2), Color(0xFFFFB347)],
    'Sunset': [Color(0xFFFF5F6D), Color(0xFFFFC371)],
    'Mint': [Color(0xFF2FD3A7), Color(0xFF4C8DFF)],
    'Mono': [Color(0xFFD4D4D8), Color(0xFF52525B)],
  };
  static const _lines = {
    OrbState.listening: 'You: “Plan a post for Saturday.”',
    OrbState.thinking: 'Thinking…',
    OrbState.speaking: 'Assistant: “Here is a Saturday post with a student offer.”',
    OrbState.idle: '',
  };

  OrbState _state = OrbState.idle;
  String _palette = 'Per state';
  double _level = 0;
  String _caption = '';
  bool _talking = false;
  late final _envelope = createTicker((elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final syllables = (math.sin(t * 9) * math.sin(t * 2.3 + 1)).abs();
    final speaking = _state == OrbState.listening || _state == OrbState.speaking;
    setState(() => _level = speaking ? 0.15 + syllables * 0.7 : 0);
  });

  @override
  void initState() {
    super.initState();
    if (Uri.base.queryParameters['autoplay'] == '1') unawaited(_converse(loop: true));
  }

  Future<void> _converse({bool loop = false}) async {
    if (_talking) return;
    setState(() => _talking = true);
    _envelope.start();
    do {
      for (final (state, ms) in const [
        (OrbState.listening, 2600),
        (OrbState.thinking, 1600),
        (OrbState.speaking, 3200),
        (OrbState.idle, 800),
      ]) {
        if (!mounted) return;
        setState(() {
          _state = state;
          _caption = _lines[state]!;
        });
        await Future<void>.delayed(Duration(milliseconds: ms));
      }
    } while (loop && mounted);
    if (!mounted) return;
    _envelope.stop();
    setState(() {
      _level = 0;
      _talking = false;
    });
  }

  @override
  void dispose() {
    _envelope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 40 + MediaQuery.paddingOf(context).bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VOICE AGENT ORB', style: text.labelSmall?.copyWith(letterSpacing: 3, color: _muted)),
                  const SizedBox(height: 10),
                  Text('Orb', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: 8),
                  Text(
                    'A shader-drawn sphere that idles, listens, thinks and speaks. Pass in your audio level and the surface follows it.',
                    style: text.bodyLarge?.copyWith(color: _muted, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _line),
                    ),
                    child: Column(
                      children: [
                        Orb(state: _state, level: _level, colors: _palettes[_palette]!, size: 280),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 22,
                          child: Text(_caption, style: text.bodyMedium?.copyWith(color: _muted)),
                        ),
                        const SizedBox(height: 16),
                        Segmented<OrbState>(
                          segments: const {
                            OrbState.idle: 'Idle',
                            OrbState.listening: 'Listen',
                            OrbState.thinking: 'Think',
                            OrbState.speaking: 'Speak',
                          },
                          selected: _state,
                          onChanged: (state) => setState(() => _state = state),
                          expand: true,
                        ),
                        const SizedBox(height: 16),
                        PillButton(
                          label: 'Simulate a conversation',
                          primary: true,
                          onPressed: _talking ? null : _converse,
                        ),
                        const SizedBox(height: 20),
                        Swatches(
                          swatches: _swatches,
                          selected: _palette,
                          onChanged: (name) => setState(() => _palette = name),
                        ),
                        const SizedBox(height: 8),
                        Text(_palette, style: text.bodySmall?.copyWith(color: _muted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'MIT © 2026 Yagnik Barasiya · respects reduced motion',
                      style: text.bodySmall?.copyWith(color: _muted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
