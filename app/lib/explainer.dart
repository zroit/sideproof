import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'theme.dart';

/// How a split-face trial works, in four animated pictures. Shown before the first trial and
/// from "How it works" on the home screen.
class ExplainerScreen extends StatefulWidget {
  const ExplainerScreen({super.key, this.doneLabel = 'Got it'});
  final String doneLabel;

  static const _seenKey = 'explainer_seen';

  /// True once the person has gone through it.
  static Future<bool> seen() async => (await SharedPreferences.getInstance()).getBool(_seenKey) ?? false;

  @override
  State<ExplainerScreen> createState() => _ExplainerScreenState();
}

class _ExplainerScreenState extends State<ExplainerScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _steps = [
    ('Sleep, weather and light change your whole face', 'So a before-and-after photo can\'t tell you what the product did.'),
    ('The product goes on one half', 'The app picks the half at random. The other half gets nothing: it is the control.'),
    ('YouCam Skin AI maps both halves', 'Each scan returns a map for every concern, like oiliness or redness. SideProof splits each map at your face\'s midline and measures the two halves.'),
    ('Only a change past the noise counts', 'Two photos before you start measure your face\'s own left-right difference and how much photos vary. The product has to beat that by 2.5 times.'),
  ];

  Future<void> _next() async {
    if (_page < _steps.length - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      return;
    }
    (await SharedPreferences.getInstance()).setBool(ExplainerScreen._seenKey, true);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('How it works')),
      body: SafeArea(
        child: Column560(
          child: Column(children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    _Step(index: i, title: _steps[i].$1, body: _steps[i].$2),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: 150,
                  child: FilledButton(onPressed: _next, child: Text(_page < _steps.length - 1 ? 'Next' : widget.doneLabel)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.title, required this.body});
  final int index;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), children: [
      Container(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.all(12),
        child: AspectRatio(aspectRatio: 1, child: ExplainerPicture(index)),
      ),
      const SizedBox(height: 24),
      Text(title, style: text.headlineSmall),
      const SizedBox(height: 10),
      Text(body, style: text.bodyLarge?.copyWith(height: 1.45, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// One of the four animated pictures. It loops while it is on screen and holds its last frame
/// when the system asks for less motion.
class ExplainerPicture extends StatefulWidget {
  const ExplainerPicture(this.index, {super.key});
  final int index;

  @override
  State<ExplainerPicture> createState() => _ExplainerPictureState();
}

class _ExplainerPictureState extends State<ExplainerPicture> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 0.999;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _phase(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.onSurface.withValues(alpha: 0.78);
    final treated = Sp.treated(context), control = Sp.control(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        switch (widget.index) {
          case 0:
            const washes = [Color(0x33F2B33D), Color(0x2E6E8CA8), Color(0x3B1F2D52)];
            const icons = [Icons.wb_sunny_outlined, Icons.cloud_outlined, Icons.bedtime_outlined];
            final k = (t * 3).floor().clamp(0, 2);
            return Stack(children: [
              Positioned.fill(child: CustomPaint(painter: FaceScene(line: line, treated: treated, control: control, wash: washes[k], split: false))),
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(icons[k], key: ValueKey(k), size: 34, color: line),
                ),
              ),
            ]);
          case 1:
            return CustomPaint(
              painter: FaceScene(line: line, treated: treated, control: control, drop: _phase(t, 0.05, 0.4), tint: t > 0.4 ? 1 : 0, spread: _phase(t, 0.4, 0.85)),
            );
          case 2:
            return CustomPaint(
              painter: FaceScene(line: line, treated: treated, control: control, tint: 1, scan: _phase(t, 0.05, 0.8), spots: 1),
            );
          default:
            return CustomPaint(
              painter: ChartScene(progress: _phase(t, 0.05, 0.8), treated: treated, control: scheme.outline, band: scheme.surfaceContainerHighest, label: scheme.onSurfaceVariant),
            );
        }
      },
    );
  }
}
