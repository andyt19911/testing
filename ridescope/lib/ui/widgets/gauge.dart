import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Sweeping arc gauge for live values, with a gradient sweep, tick marks and a
/// colour that shifts to amber/red as the value nears the top of its range.
class ArcGauge extends StatelessWidget {
  const ArcGauge({super.key, required this.value, required this.min, required this.max, required this.unit});
  final double? value;
  final double min;
  final double max;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final v = value;
    final f = v == null || max <= min ? 0.0 : ((v - min) / (max - min)).clamp(0.0, 1.0);
    final color = f > 0.92 ? rs.bad : (f > 0.82 ? rs.warn : rs.accent);
    return AspectRatio(
      aspectRatio: 1.35,
      child: CustomPaint(
        painter: _ArcPainter(f, color, rs.accent2, rs.surface3),
        child: Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
              child: Text(v == null ? '—' : _fmt(v),
                  style: context.text.displaySmall?.copyWith(fontSize: 34, fontFeatures: tabular, color: color)),
            ),
            Text(unit, style: context.text.bodySmall),
          ]),
        ),
      ),
    );
  }

  String _fmt(double v) => v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.fraction, this.color, this.color2, this.track);
  final double fraction;
  final Color color;
  final Color color2;
  final Color track;

  static const _start = pi * 0.75;
  static const _sweep = pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height * 1.35) / 2 - 10;
    final c = Offset(size.width / 2, size.height / 2 + 12);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = this.track;
    canvas.drawArc(rect, _start, _sweep, false, track);

    // Ticks around the arc.
    final tick = Paint()
      ..color = this.track
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const ticks = 11;
    for (var i = 0; i <= ticks; i++) {
      final a = _start + _sweep * (i / ticks);
      final outer = c + Offset(cos(a), sin(a)) * (r + 10);
      final inner = c + Offset(cos(a), sin(a)) * (r + 15);
      canvas.drawLine(inner, outer, tick);
    }

    // Value sweep with a gradient.
    if (fraction > 0) {
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [color2, color],
          transform: GradientRotation(_start),
        ).createShader(rect);
      canvas.drawArc(rect, _start, _sweep * fraction, false, sweep);

      // Glowing endpoint.
      final a = _start + _sweep * fraction;
      final p = c + Offset(cos(a), sin(a)) * r;
      canvas.drawCircle(p, 6, Paint()..color = color..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.fraction != fraction || old.color != color;
}
