import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'brand.dart';
import 'theme.dart';

/// A trial's status in the words the person would use.
String statusWords(String status) => switch (status) {
      'baseline' => 'Taking the baseline photos',
      'running' => 'In progress',
      'concluding' => 'Ready for the verdict',
      'done' => 'Finished',
      'stopped' => 'Stopped: the treated half got worse',
      _ => status,
    };

/// The treated half, shaded: on the person's own photo when the app has one, else on the face
/// drawing. The photo is shown as taken, so the shaded half is on the same side as in the photo.
class HalfShade extends StatelessWidget {
  const HalfShade({super.key, required this.imageLeft, this.photo, this.height = 260});

  final bool imageLeft;
  final Uint8List? photo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Sp.treated(context);
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: height,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(fit: StackFit.expand, children: [
            if (photo != null)
              Image.memory(photo!, fit: BoxFit.cover)
            else
              Container(
                color: scheme.surfaceContainer,
                child: Transform.flip(
                  flipX: imageLeft,
                  child: CustomPaint(painter: FaceScene(line: scheme.onSurface.withValues(alpha: 0.7), treated: color, control: Sp.control(context), tint: 1)),
                ),
              ),
            if (photo != null)
              Align(
                alignment: imageLeft ? Alignment.centerLeft : Alignment.centerRight,
                child: FractionallySizedBox(widthFactor: 0.5, heightFactor: 1, child: Container(color: color.withValues(alpha: 0.38))),
              ),
            Center(child: Container(width: 2.5, color: color)),
            Align(
              alignment: imageLeft ? const Alignment(-0.5, 0.86) : const Alignment(0.5, 0.86),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(gradient: Sp.cta, borderRadius: BorderRadius.circular(99)),
                child: Text('Product here', style: body(12, weight: 700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One concern over time: the treated half minus the control half, after the face's own
/// asymmetry is taken out. The band is the noise; points below it mean less of the concern.
/// The line draws itself in once, left to right.
class EffectChart extends StatelessWidget {
  const EffectChart({super.key, required this.stats, this.compact = false});
  final Map<String, dynamic> stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: compact ? 96 : 160,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 1600),
        curve: Curves.easeInOutCubic,
        builder: (context, drawn, _) => CustomPaint(
          size: Size.infinite,
          painter: _EffectPainter(
            series: List<Map<String, dynamic>>.from(stats['series'] ?? []),
            threshold: (stats['threshold'] as num?)?.toDouble() ?? 1,
            treated: Sp.treated(context),
            mute: Sp.outline,
            compact: compact,
            drawn: drawn,
          ),
        ),
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter({required this.series, required this.threshold, required this.treated, required this.mute, required this.compact, required this.drawn});

  static const band = Color(0xFFF3E8E4);
  static const line = LinearGradient(colors: [Color(0xFFF48FB1), Color(0xFFE3507E), Color(0xFFB467E0)], stops: [0, 0.5, 1]);

  final List<Map<String, dynamic>> series;
  final double threshold, drawn;
  final Color treated, mute;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final left = compact ? 0.0 : 44.0, bottom = compact ? 4.0 : 20.0;
    final w = size.width - left, h = size.height - bottom;
    final hours = series.map((s) => (s['hours'] as num).toDouble()).toList();
    final effects = series.map((s) => (s['effect'] as num).toDouble()).toList();
    final maxH = max(1.0, hours.reduce(max));
    final span = [threshold * 1.6, ...effects.map((e) => e.abs() * 1.15)].reduce(max);
    double x(double hr) => left + 8 + hr / maxH * (w - 16);
    double y(double e) => h / 2 - e / span * (h / 2 - 6);

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(left, y(threshold), size.width, y(-threshold)), const Radius.circular(11)), Paint()..color = band);
    canvas.drawLine(Offset(left, y(0)), Offset(size.width, y(0)), Paint()
      ..color = mute.withValues(alpha: 0.5)
      ..strokeWidth = 1);
    if (!compact) {
      _text(canvas, 'worse', const Offset(0, 0), mute);
      _text(canvas, 'better', Offset(0, h - 14), mute);
      _text(canvas, 'noise', Offset(0, y(0) - 7), mute);
      _text(canvas, '0 h', Offset(left + 2, h + 4), mute);
      _text(canvas, '${maxH.toStringAsFixed(0)} h', Offset(size.width - 28, h + 4), mute);
    }

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final o = Offset(x(hours[i]), y(effects[i]));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final shown = Path();
    for (final m in path.computeMetrics()) {
      shown.addPath(m.extractPath(0, m.length * drawn), Offset.zero);
    }
    canvas.drawPath(shown, Paint()
      ..shader = line.createShader(Rect.fromLTRB(left, 0, size.width, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 3 : 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    final reach = left + 8 + drawn * (w - 16);
    for (var i = 0; i < series.length; i++) {
      final baseline = series[i]['phase'] == 'baseline';
      final at = Offset(x(hours[i]), y(effects[i]));
      if (at.dx > reach + 0.5) continue;
      canvas.drawCircle(at, compact ? 5 : 6, Paint()..color = baseline ? mute : treated);
      if (!baseline) canvas.drawCircle(at, compact ? 2 : 2.4, Paint()..color = Colors.white);
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color) {
    (TextPainter(text: TextSpan(text: s, style: body(11, weight: 700, color: color)), textDirection: TextDirection.ltr)..layout()).paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) => true;
}

class VerdictChip extends StatelessWidget {
  const VerdictChip(this.verdict, {super.key});
  final String? verdict;

  @override
  Widget build(BuildContext context) => ResultPill(
        switch (verdict) {
          'better' => 'Better',
          'worse' => 'Worse',
          'unclear' => 'Too early to tell',
          _ => 'Waiting for scans',
        },
        verdict,
      );
}

/// A result in its colour: green for better, amber for too early, red for worse, with a tick
/// when it came out better.
class ResultPill extends StatelessWidget {
  const ResultPill(this.label, this.verdict, {super.key});
  final String label;
  final String? verdict;

  @override
  Widget build(BuildContext context) {
    final color = verdict == null ? Sp.muted : Sp.verdict(verdict, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: Sp.verdictBg(verdict), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (verdict == 'better') ...[Icon(Icons.check_rounded, size: 14, color: color), const SizedBox(width: 4)],
        Flexible(child: Text(label, style: body(12.5, weight: 800, color: color))),
      ]),
    );
  }
}

/// How far a concern moved, as a ring: the effect in multiples of the noise threshold. A full
/// sweep is 4 times the threshold; a result inside the noise stays a short arc.
class VerdictRing extends StatelessWidget {
  const VerdictRing({super.key, this.effect, this.threshold, this.verdict, this.size = 104});
  final double? effect, threshold;
  final String? verdict;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = threshold ?? 0;
    final ratio = effect != null && t > 0 ? effect!.abs() / t : 0.0;
    final share = max(0.04, min(1.0, ratio / 4));
    final colors = switch (verdict) {
      'worse' => const [Color(0xFFF2A08F), Color(0xFFB23A2E)],
      'better' => const [Color(0xFFF48FB1), Color(0xFFB467E0)],
      _ => const [Color(0xFFF7C98E), Color(0xFFD9893A)],
    };
    final still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'The change is ${ratio.toStringAsFixed(1)} times the noise',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? share : 0, end: share),
        duration: const Duration(milliseconds: 1400),
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        builder: (context, sweep, _) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(sweep, colors),
          child: SizedBox.square(
            dimension: size,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${ratio.toStringAsFixed(1)}\u00d7', style: display(size * 0.28, color: Sp.ink, height: 1)),
              const SizedBox(height: 3),
              Text(ratio >= 1 ? 'past the noise' : 'of the noise', style: body(size * 0.088, weight: 700, color: Sp.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.sweep, this.colors);
  final double sweep;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 12 / 112;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2 - 2);
    canvas.drawCircle(rect.center, rect.width / 2, Paint()
      ..color = const Color(0xFFF3E8E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(rect, -pi / 2, 2 * pi * sweep, false, Paint()
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.sweep != sweep || old.colors != colors;
}

/// Where the trial is: baseline photos, product on, scans, verdict.
class TrialTimeline extends StatelessWidget {
  const TrialTimeline({super.key, required this.step, required this.notes});

  /// 0 baseline, 1 product on, 2 scans, 3 verdict.
  final int step;
  final List<String> notes;

  static const _names = ['Baseline', 'Product on', 'Scans', 'Verdict'];

  /// Together the four bars run pink, rose, lilac, mint.
  static const _bars = [
    [Color(0xFFF48FB1), Color(0xFFE3507E)],
    [Color(0xFFE3507E), Color(0xFFC25BC8)],
    [Color(0xFFC25BC8), Color(0xFF8C6BE8)],
    [Color(0xFF8C6BE8), Color(0xFF3BB8A3)],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final finished = step >= _names.length - 1;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < _names.length; i++)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Opacity(
              opacity: i == step && !finished ? 0.5 : 1,
              child: Container(
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: i <= step || finished ? null : Sp.line,
                  gradient: i <= step || finished ? LinearGradient(colors: _bars[i]) : null,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(_names[i], style: body(12.5, weight: i == step ? 800 : 700, color: i <= step ? scheme.onSurface : scheme.onSurfaceVariant)),
            if (i < notes.length && notes[i].isNotEmpty) Text(notes[i], style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
    ]);
  }
}

/// The verdict as a picture: the split disc, its treated half in the colour of the result.
class VerdictDisc extends StatelessWidget {
  const VerdictDisc({super.key, required this.verdict, this.size = 64});
  final String? verdict;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _DiscPainter(Sp.verdict(verdict, context), Theme.of(context).colorScheme.outlineVariant));
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.result, this.control);
  final Color result, control;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2 - 3, gap = size.shortestSide * 0.06;
    canvas.drawPath(Path()
      ..addArc(Rect.fromCircle(center: c.translate(-gap / 2, 0), radius: r), pi / 2, pi)
      ..close(), Paint()..color = control);
    canvas.drawPath(Path()
      ..addArc(Rect.fromCircle(center: c.translate(gap / 2, 0), radius: r), -pi / 2, pi)
      ..close(), Paint()..color = result);
  }

  @override
  bool shouldRepaint(covariant _DiscPainter old) => old.result != result || old.control != control;
}

/// What to do before each photo, so the two halves are lit and framed the same way.
class PhotoTips extends StatelessWidget {
  const PhotoTips({super.key});

  static const _tips = [
    (Icons.wb_twilight_outlined, 'Face a window', 'Even light on both halves'),
    (Icons.face_retouching_off_outlined, 'Bare skin', 'No makeup, hair back'),
    (Icons.center_focus_strong_outlined, 'Look straight', 'Phone at eye level'),
    (Icons.place_outlined, 'Same spot', 'Same place every time'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.15,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final (icon, title, sub) in _tips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Sp.sunk, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(sub, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

/// The treated half of a photo, cut along the face's midline ([x0, x1] as fractions of width,
/// top and bottom).
class HalfClipper extends CustomClipper<Path> {
  HalfClipper(this.midline, this.treatedLeft);
  final List<double> midline;
  final bool treatedLeft;

  @override
  Path getClip(Size s) {
    final a = midline[0] * s.width, b = midline[1] * s.width;
    return treatedLeft
        ? (Path()..moveTo(0, 0)..lineTo(a, 0)..lineTo(b, s.height)..lineTo(0, s.height)..close())
        : (Path()..moveTo(a, 0)..lineTo(s.width, 0)..lineTo(s.width, s.height)..lineTo(b, s.height)..close());
  }

  @override
  bool shouldReclip(covariant HalfClipper old) => old.midline != midline || old.treatedLeft != treatedLeft;
}

class _Midline extends CustomPainter {
  _Midline(this.midline, this.color);
  final List<double> midline;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final top = Offset(midline[0] * s.width, 0), bottom = Offset(midline[1] * s.width, s.height);
    final steps = (s.height / 14).floor();
    for (var i = 0; i < steps; i += 2) {
      canvas.drawLine(Offset.lerp(top, bottom, i / steps)!, Offset.lerp(top, bottom, (i + 1) / steps)!, p);
    }
  }

  @override
  bool shouldRepaint(covariant _Midline old) => old.midline != midline || old.color != color;
}

/// A face photo split at its midline: YouCam's map on top (or, for the promise, YouCam's
/// simulated photo on the treated half), each half labelled with what YouCam measured.
class SplitPhoto extends StatelessWidget {
  const SplitPhoto({super.key, required this.photo, required this.midline, required this.treatedLeft, this.overlay, this.treatedPhoto, this.tint = false, this.labels});
  final ImageProvider photo;
  final ImageProvider? overlay, treatedPhoto;
  final List<double> midline;
  final bool treatedLeft, tint;
  final (String control, String treated)? labels;

  @override
  Widget build(BuildContext context) {
    final cobalt = Sp.treated(context);
    Widget pill(String text, bool treated) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: treated ? null : Colors.white.withValues(alpha: 0.9),
            gradient: treated ? Sp.cta : null,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(text, style: body(12, weight: 800, color: treated ? Colors.white : Sp.ink)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(children: [
        Image(image: photo, width: double.infinity, fit: BoxFit.fitWidth),
        if (treatedPhoto != null) Positioned.fill(child: ClipPath(clipper: HalfClipper(midline, treatedLeft), child: Image(image: treatedPhoto!, fit: BoxFit.fill))),
        if (tint) Positioned.fill(child: ClipPath(clipper: HalfClipper(midline, treatedLeft), child: Container(color: cobalt.withValues(alpha: treatedPhoto != null ? 0.12 : 0.32)))),
        if (overlay != null) Positioned.fill(child: Image(image: overlay!, fit: BoxFit.fill, gaplessPlayback: true)),
        Positioned.fill(child: CustomPaint(painter: _Midline(midline, cobalt))),
        if (labels != null)
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: treatedLeft ? TextDirection.rtl : TextDirection.ltr,
              children: [pill(labels!.$1, false), pill(labels!.$2, true)],
            ),
          ),
      ]),
    );
  }
}

/// What YouCam saw on the latest photo, one concern at a time.
class YouCamView extends StatefulWidget {
  const YouCamView({super.key, required this.photo, required this.overlays, required this.midline, required this.treatedLeft, required this.concerns});
  final ImageProvider photo;
  final Map<String, ImageProvider> overlays;
  final List<double> midline;
  final bool treatedLeft;
  final Map<String, dynamic> concerns;

  @override
  State<YouCamView> createState() => _YouCamViewState();
}

class _YouCamViewState extends State<YouCamView> {
  String? _shown;

  @override
  Widget build(BuildContext context) {
    final keys = widget.overlays.keys.where(widget.concerns.containsKey).toList();
    if (keys.isEmpty) return const SizedBox.shrink();
    final shown = keys.contains(_shown) ? _shown! : keys.first;
    final stats = widget.concerns[shown] as Map<String, dynamic>;
    final series = (stats['series'] as List?) ?? const [];
    final last = series.isEmpty ? null : series.last as Map<String, dynamic>;
    String pct(dynamic v) => '${(v as num).toStringAsFixed(1)}%';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (keys.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SegmentedButton<String>(
            segments: [for (final k in keys) ButtonSegment(value: k, label: Text((widget.concerns[k] as Map)['label'] ?? k))],
            selected: {shown},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _shown = s.first),
          ),
        ),
      SplitPhoto(
        photo: widget.photo,
        overlay: widget.overlays[shown],
        midline: widget.midline,
        treatedLeft: widget.treatedLeft,
        labels: last == null ? null : ('Control ${pct(last['control'])}', 'Treated ${pct(last['treated'])}'),
      ),
    ]);
  }
}

/// Two pictures of the same face; drag across to wipe from one to the other. It sweeps once on
/// its own so it is clear there is something to drag; a close-up shows where the claim acts.
class CompareSlider extends StatefulWidget {
  const CompareSlider({super.key, required this.before, required this.after, required this.beforeLabel, required this.afterLabel, this.closeUp});
  final ImageProvider before, after;
  final String beforeLabel, afterLabel;
  final (double scale, Alignment focus, String label)? closeUp;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  double _pos = 0.5;
  bool _touched = false;
  late bool _zoom = widget.closeUp != null;

  @override
  void initState() {
    super.initState();
    _sweep.addListener(() {
      if (!_touched) setState(() => _pos = 0.5 + 0.38 * sin(_sweep.value * pi * 2) * (1 - _sweep.value * 0.3));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations && !_sweep.isAnimating && _sweep.value == 0) {
      Future.delayed(const Duration(milliseconds: 600), () => mounted && !_touched ? _sweep.forward() : null);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = widget.closeUp;
    Widget lens(Widget child) => _zoom && c != null ? Transform.scale(scale: c.$1, alignment: c.$2, child: child) : child;
    Widget corner(String text, bool right) => Positioned(
          top: 10,
          left: right ? null : 10,
          right: right ? 10 : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: right ? Sp.lilac : Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(99)),
            child: Text(text, style: body(12, weight: 800, color: right ? Colors.white : Sp.ink)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: LayoutBuilder(builder: (context, box) {
          void drag(double dx) => setState(() {
                _touched = true;
                _pos = (dx / box.maxWidth).clamp(0.0, 1.0);
              });
          return GestureDetector(
            onHorizontalDragStart: (d) => drag(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => drag(d.localPosition.dx),
            onTapDown: (d) => drag(d.localPosition.dx),
            child: Stack(children: [
              lens(Image(image: widget.before, width: double.infinity, fit: BoxFit.fitWidth)),
              Positioned.fill(child: ClipRect(clipper: _FromLeft(_pos), child: lens(Image(image: widget.after, fit: BoxFit.fill)))),
              Positioned(
                left: _pos * box.maxWidth - 1.5,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: Colors.white),
              ),
              Positioned(
                left: _pos * box.maxWidth - 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10)]),
                    child: const Icon(Icons.compare_arrows, size: 22, color: Sp.ink),
                  ),
                ),
              ),
              corner(widget.beforeLabel, false),
              corner(widget.afterLabel, true),
            ]),
          );
        }),
      ),
      if (c != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SegmentedButton<bool>(
            segments: [ButtonSegment(value: true, label: Text(c.$3)), const ButtonSegment(value: false, label: Text('Whole face'))],
            selected: {_zoom},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(foregroundColor: scheme.onSurface),
            onSelectionChanged: (s) => setState(() => _zoom = s.first),
          ),
        ),
    ]);
  }
}

class _FromLeft extends CustomClipper<Rect> {
  _FromLeft(this.pos);
  final double pos;
  @override
  Rect getClip(Size s) => Rect.fromLTRB(s.width * pos, 0, s.width, s.height);
  @override
  bool shouldReclip(covariant _FromLeft old) => old.pos != pos;
}

/// Where to look closely for a claim: the forehead for shine, a cheek on the treated half for
/// redness, pores and spots.
(double, Alignment, String) closeUpFor(List<String> concerns, bool treatedLeft) => concerns.contains('oiliness')
    ? (2.2, const Alignment(0, -0.56), 'Close-up: forehead')
    : (2.3, Alignment(treatedLeft ? -0.36 : 0.36, 0.12), 'Close-up: cheek');
