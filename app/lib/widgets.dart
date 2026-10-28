import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The treated half, shaded: on the person's own photo when the app has one, else on a face outline.
class HalfShade extends StatelessWidget {
  const HalfShade({super.key, required this.imageLeft, this.photo, this.height = 220});

  final bool imageLeft;
  final Uint8List? photo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final shade = Align(
      alignment: imageLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: FractionallySizedBox(widthFactor: 0.5, heightFactor: 1, child: Container(color: color.withValues(alpha: 0.35))),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(fit: StackFit.expand, children: [
            if (photo != null)
              Image.memory(photo!, fit: BoxFit.cover)
            else
              CustomPaint(painter: _FaceOutline(Theme.of(context).colorScheme.outline)),
            shade,
            Center(child: Container(width: 2, color: color)),
          ]),
        ),
      ),
    );
  }
}

class _FaceOutline extends CustomPainter {
  _FaceOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final face = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.62, height: size.height * 0.78);
    canvas.drawOval(face, p);
    final eyeY = face.top + face.height * 0.42;
    for (final dx in [-0.18, 0.18]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(size.width / 2 + face.width * dx, eyeY), width: face.width * 0.16, height: face.height * 0.05), p);
    }
    canvas.drawArc(Rect.fromCenter(center: Offset(size.width / 2, face.top + face.height * 0.74), width: face.width * 0.3, height: face.height * 0.08), 0.2, 2.7, false, p);
  }

  @override
  bool shouldRepaint(covariant _FaceOutline old) => old.color != color;
}

/// One concern over time: the treated half minus the control half, after the face's own
/// asymmetry is taken out. The band is the noise; points below it mean less of the concern.
class EffectChart extends StatelessWidget {
  const EffectChart({super.key, required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: CustomPaint(
        size: Size.infinite,
        painter: _EffectPainter(
          series: List<Map<String, dynamic>>.from(stats['series'] ?? []),
          threshold: (stats['threshold'] as num?)?.toDouble() ?? 1,
          ink: scheme.onSurface,
          band: scheme.surfaceContainerHighest,
          accent: scheme.primary,
          mute: scheme.outline,
        ),
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter({required this.series, required this.threshold, required this.ink, required this.band, required this.accent, required this.mute});

  final List<Map<String, dynamic>> series;
  final double threshold;
  final Color ink, band, accent, mute;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    const left = 34.0, bottom = 18.0;
    final w = size.width - left, h = size.height - bottom;
    final hours = series.map((s) => (s['hours'] as num).toDouble()).toList();
    final effects = series.map((s) => (s['effect'] as num).toDouble()).toList();
    final maxH = hours.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    final span = [threshold * 1.6, ...effects.map((e) => e.abs() * 1.15)].reduce((a, b) => a > b ? a : b);
    double x(double hr) => left + hr / maxH * w;
    double y(double e) => h / 2 - e / span * (h / 2);

    canvas.drawRect(Rect.fromLTRB(left, y(threshold), size.width, y(-threshold)), Paint()..color = band);
    canvas.drawLine(Offset(left, y(0)), Offset(size.width, y(0)), Paint()..color = mute..strokeWidth = 1);
    _text(canvas, 'worse', Offset(0, 2), mute);
    _text(canvas, 'better', Offset(0, h - 14), mute);
    _text(canvas, '0 h', Offset(left, h + 3), mute);
    _text(canvas, '${maxH.toStringAsFixed(0)} h', Offset(size.width - 26, h + 3), mute);

    final line = Path();
    for (var i = 0; i < series.length; i++) {
      final o = Offset(x(hours[i]), y(effects[i]));
      i == 0 ? line.moveTo(o.dx, o.dy) : line.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(line, Paint()..color = accent.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 2);
    for (var i = 0; i < series.length; i++) {
      final baseline = series[i]['phase'] == 'baseline';
      canvas.drawCircle(Offset(x(hours[i]), y(effects[i])), 4.5, Paint()..color = baseline ? mute : accent);
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color) {
    (TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: color)), textDirection: TextDirection.ltr)..layout())
        .paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) => true;
}

class VerdictChip extends StatelessWidget {
  const VerdictChip(this.verdict, {super.key});
  final String? verdict;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (verdict) {
      'better' => ('Better', const Color(0xFF2F7D5B)),
      'worse' => ('Worse', const Color(0xFFB4442F)),
      'unclear' => ('Too early to tell', Theme.of(context).colorScheme.outline),
      _ => ('Waiting for scans', Theme.of(context).colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
