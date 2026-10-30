import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// The mark: a face split down the middle. The filled half had the product, the outlined half is
/// the control; a closed eye on each. The same geometry as the web's 32x32 SVG.
class SideProofMark extends StatelessWidget {
  const SideProofMark({super.key, this.size = 28, this.light = false});
  final double size;
  final bool light; // white, for a coloured background

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter(light));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.light);
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 32;
    canvas.save();
    canvas.scale(k);
    final left = Path()
      ..moveTo(15, 2.6)
      ..cubicTo(8.6, 3, 4.8, 8.3, 4.8, 14.6)
      ..cubicTo(4.8, 21.6, 9.2, 27.6, 15, 29.5)
      ..close();
    final right = Path()
      ..moveTo(17.2, 3.9)
      ..cubicTo(22.6, 4.8, 25.8, 9.3, 25.8, 14.6)
      ..cubicTo(25.8, 20.6, 22.3, 25.6, 17.2, 27.8)
      ..close();
    final ink = light ? Colors.white : Sp.ink;
    canvas.drawPath(left, Paint()..shader = light ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF48FB1), Color(0xFFE3507E), Color(0xFFB467E0)], stops: [0, .55, 1]).createShader(const Rect.fromLTWH(0, 0, 32, 32))
      ..color = light ? Colors.white : Sp.rose);
    canvas.drawPath(right, Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round);
    Path eye(double x) => Path()
      ..moveTo(x, 13.4)
      ..cubicTo(x + 0.8, 14.2, x + 2.2, 14.2, x + 3, 13.4);
    final lid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(eye(9.6), lid..color = light ? Sp.rose : Sp.cream);
    canvas.drawPath(eye(19.6), lid..color = ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.light != light;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SideProofMark(size: size * 1.2),
        SizedBox(width: size * 0.4),
        Text('SideProof', style: display(size * 1.3, color: Sp.ink)),
      ]);
}

/// A face drawn in line, split at the midline. Everything the explainer and the home screen
/// show is a state of this one drawing: the product spreading on the treated half, a wash over
/// the whole face, a scan line, and the spots a scan finds.
class FaceScene extends CustomPainter {
  FaceScene({
    required this.line,
    required this.treated,
    required this.control,
    this.tint = 0,
    this.spread = 1,
    this.drop,
    this.wash,
    this.scan,
    this.spots = 0,
    this.spotsFade = 0,
    this.split = true,
  });

  final Color line, treated, control;
  final double tint; // 0..1, how strongly the treated half is coloured
  final double spread; // 0..1, the product spreading from the cheek
  final double? drop; // 0..1, a drop falling onto the treated cheek
  final Color? wash; // light or weather over the whole face
  final double? scan; // 0..1, the scan line from forehead to chin
  final double spots; // 0..1, spots shown
  final double spotsFade; // 0..1, spots fading on the treated half
  final bool split; // false: one face, no halves yet

  static final List<Offset> _spots = () {
    final r = Random(7);
    return [for (var i = 0; i < 34; i++) Offset(r.nextDouble() * 0.8 + 0.1, r.nextDouble() * 0.7 + 0.18)];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final head = Rect.fromCenter(center: Offset(w / 2, h * 0.46), width: w * 0.52, height: h * 0.68);
    final cx = head.center.dx;
    final headPath = Path()..addOval(head);
    final treatedHalf = Rect.fromLTRB(cx, head.top, head.right, head.bottom);
    final cheek = Offset(cx + head.width * 0.22, head.top + head.height * 0.62);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.6, w * 0.008)
      ..strokeCap = StrokeCap.round;

    // Neck and shoulders, so the head sits on something.
    final neckTop = head.bottom - head.height * 0.04;
    canvas.drawLine(Offset(cx - head.width * 0.17, neckTop), Offset(cx - head.width * 0.17, h * 0.9), stroke);
    canvas.drawLine(Offset(cx + head.width * 0.17, neckTop), Offset(cx + head.width * 0.17, h * 0.9), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.1, h)
        ..quadraticBezierTo(w * 0.14, h * 0.88, cx - head.width * 0.17, h * 0.88)
        ..moveTo(w * 0.9, h)
        ..quadraticBezierTo(w * 0.86, h * 0.88, cx + head.width * 0.17, h * 0.88),
      stroke,
    );

    canvas.save();
    canvas.clipPath(headPath);
    if (split) canvas.drawRect(Rect.fromLTRB(head.left, head.top, cx, head.bottom), Paint()..color = control.withValues(alpha: 0.28));
    if (wash != null) canvas.drawRect(head, Paint()..color = wash!);
    if (tint > 0) {
      canvas.save();
      canvas.clipRect(treatedHalf);
      final reach = head.height * 1.1 * Curves.easeOutCubic.transform(spread.clamp(0, 1));
      canvas.drawCircle(cheek, reach, Paint()..color = treated.withValues(alpha: 0.32 * tint));
      canvas.restore();
    }
    if (spots > 0) {
      for (final s in _spots) {
        final p = Offset(head.left + s.dx * head.width, head.top + s.dy * head.height);
        if (scan != null && p.dy > head.top + head.height * scan!) continue;
        final onTreated = p.dx > cx;
        final a = spots * (onTreated ? 1 - spotsFade * 0.8 : 1);
        if (a <= 0.02) continue;
        canvas.drawCircle(p, w * 0.012, Paint()..color = line.withValues(alpha: 0.55 * a));
      }
    }
    if (scan != null && scan! > 0 && scan! < 1) {
      final y = head.top + head.height * scan!;
      canvas.drawRect(
        Rect.fromLTRB(head.left, y - h * 0.06, head.right, y),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [treated.withValues(alpha: 0), treated.withValues(alpha: 0.35)],
          ).createShader(Rect.fromLTRB(0, y - h * 0.06, w, y)),
      );
      canvas.drawLine(Offset(head.left, y), Offset(head.right, y), Paint()
        ..color = treated
        ..strokeWidth = 2);
    }
    canvas.restore();

    // The head and its features.
    canvas.drawOval(head, stroke);
    final eyeY = head.top + head.height * 0.45;
    for (final side in [-1, 1]) {
      final ex = cx + side * head.width * 0.2;
      canvas.drawArc(Rect.fromCenter(center: Offset(ex, eyeY), width: head.width * 0.17, height: head.height * 0.07), pi * 1.1, pi * 0.8, false, stroke);
      canvas.drawLine(Offset(ex - head.width * 0.09, eyeY - head.height * 0.08), Offset(ex + head.width * 0.08, eyeY - head.height * 0.095), stroke);
    }
    canvas.drawPath(
      Path()
        ..moveTo(cx + head.width * 0.01, eyeY + head.height * 0.04)
        ..lineTo(cx - head.width * 0.05, eyeY + head.height * 0.2)
        ..lineTo(cx + head.width * 0.03, eyeY + head.height * 0.21),
      stroke,
    );
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, head.top + head.height * 0.77), width: head.width * 0.28, height: head.height * 0.08), 0.25, pi - 0.5, false, stroke);

    // The hair, over the halves, so the midline runs from the hairline to the chin.
    Offset at(double fx, double fy) => Offset(head.left + fx * head.width, head.top + fy * head.height);
    final a = at(0.023, 0.357), b = at(0.5, -0.063), c = at(0.977, 0.357), d = at(0.5, _hairline);
    final p1 = at(-0.068, 0.054), p2 = at(0.205, -0.063), p3 = at(0.795, -0.063), p4 = at(1.068, 0.054);
    final p5 = at(0.909, 0.214), p6 = at(0.727, _hairline), p7 = at(0.273, _hairline), p8 = at(0.091, 0.214);
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, b.dx, b.dy)
        ..cubicTo(p3.dx, p3.dy, p4.dx, p4.dy, c.dx, c.dy)
        ..cubicTo(p5.dx, p5.dy, p6.dx, p6.dy, d.dx, d.dy)
        ..cubicTo(p7.dx, p7.dy, p8.dx, p8.dy, a.dx, a.dy)
        ..close(),
      Paint()..color = const Color(0xFF5A3D46),
    );

    // The midline, dashed, in the treated colour.
    if (split) _midline(canvas, head, cx, w, h);

    if (drop != null && drop! < 1) {
      _drop(canvas, cheek, w, h);
    }
  }

  void _midline(Canvas canvas, Rect head, double cx, double w, double h) {
    final dash = Paint()
      ..color = treated
      ..strokeWidth = max(1.4, w * 0.006);
    for (var y = head.top + head.height * _hairline; y < head.bottom; y += h * 0.035) {
      canvas.drawLine(Offset(cx, y), Offset(cx, min(y + h * 0.018, head.bottom)), dash);
    }
  }

  static const _hairline = 0.134; // of the head's height

  void _drop(Canvas canvas, Offset cheek, double w, double h) {
    final t = Curves.easeIn.transform(drop!);
    final at = Offset(cheek.dx, h * 0.02 + (cheek.dy - h * 0.02) * t);
    final d = w * 0.035;
    canvas.drawPath(
      Path()
        ..moveTo(at.dx, at.dy - d * 1.6)
        ..quadraticBezierTo(at.dx + d, at.dy - d * 0.2, at.dx, at.dy + d * 0.6)
        ..quadraticBezierTo(at.dx - d, at.dy - d * 0.2, at.dx, at.dy - d * 1.6),
      Paint()..color = treated,
    );
  }

  @override
  bool shouldRepaint(covariant FaceScene old) => true;
}


/// The idea of the trial as a chart: the control half wanders inside the noise band, the
/// treated half leaves it. [progress] draws the lines from left to right.
class ChartScene extends CustomPainter {
  ChartScene({required this.progress, required this.treated, required this.control, required this.band, required this.label});
  final double progress;
  final Color treated, control, band, label;

  static const _controlPts = [0.0, 0.05, -0.08, 0.06, -0.03, 0.07, -0.05, 0.02];
  static const _treatedPts = [0.02, -0.06, -0.35, -0.55, -0.66, -0.72, -0.7, -0.74];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.12, bottom = h * 0.86, left = w * 0.06, right = w * 0.94;
    double y(double v) => (top + bottom) / 2 - v * (bottom - top) / 2;
    double x(int i) => left + i / (_controlPts.length - 1) * (right - left);
    final bandHalf = 0.16;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(left, y(bandHalf), right, y(-bandHalf)), const Radius.circular(8)),
      Paint()..color = band,
    );
    _text(canvas, 'noise', Offset(right - 40, y(bandHalf) - 18), label);
    _text(canvas, 'baseline', Offset(left, bottom + 4), label);
    _text(canvas, 'after the product', Offset(right - 104, bottom + 4), label);
    final baselineEnd = x(1) + (x(2) - x(1)) / 2;
    canvas.drawLine(Offset(baselineEnd, top), Offset(baselineEnd, bottom), Paint()
      ..color = label.withValues(alpha: 0.35)
      ..strokeWidth = 1);

    void series(List<double> pts, Color color, double width) {
      final n = (pts.length - 1) * progress.clamp(0, 1);
      final path = Path()..moveTo(x(0), y(pts[0]));
      for (var i = 1; i <= n.floor(); i++) {
        path.lineTo(x(i), y(pts[i]));
      }
      final frac = n - n.floor();
      if (frac > 0 && n.floor() + 1 < pts.length) {
        final i = n.floor();
        path.lineTo(x(i) + (x(i + 1) - x(i)) * frac, y(pts[i] + (pts[i + 1] - pts[i]) * frac));
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
    }

    series(_controlPts, control, 3);
    series(_treatedPts, treated, 3.5);
    // Legend, top left.
    canvas.drawLine(Offset(left, h * 0.03 + 7), Offset(left + 18, h * 0.03 + 7), Paint()
      ..color = treated
      ..strokeWidth = 3.5);
    _text(canvas, 'treated half', Offset(left + 24, h * 0.03), label);
    canvas.drawLine(Offset(left + 112, h * 0.03 + 7), Offset(left + 130, h * 0.03 + 7), Paint()
      ..color = control
      ..strokeWidth = 3);
    _text(canvas, 'control half', Offset(left + 136, h * 0.03), label);
  }

  void _text(Canvas canvas, String s, Offset at, Color color) =>
      (TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)), textDirection: TextDirection.ltr)..layout())
          .paint(canvas, at);

  @override
  bool shouldRepaint(covariant ChartScene old) => true;
}
