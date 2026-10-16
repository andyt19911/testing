import 'dart:math';

import 'package:flutter/material.dart';

/// Arc gauge for live values. Colour shifts to amber/red in the top 15/5%
/// of the range.
class ArcGauge extends StatelessWidget {
  const ArcGauge({super.key, required this.value, required this.min, required this.max, required this.label, required this.unit});
  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value;
    final f = v == null || max <= min ? 0.0 : ((v - min) / (max - min)).clamp(0.0, 1.0);
    final color = f > 0.95
        ? const Color(0xFFE5484D)
        : f > 0.85
            ? const Color(0xFFF2A93B)
            : scheme.primary;
    return AspectRatio(
      aspectRatio: 1.25,
      child: CustomPaint(
        painter: _ArcPainter(f, color, scheme.surfaceContainerHigh),
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
              child: Text(
                v == null ? '—' : _fmt(v),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            Text(unit, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  String _fmt(double v) => v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.fraction, this.color, this.track);
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const start = pi * 0.75;
    const sweep = pi * 1.5;
    final r = min(size.width, size.height * 1.25) / 2 - 8;
    final c = Offset(size.width / 2, size.height / 2 + 10);
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, p..color = track);
    if (fraction > 0) canvas.drawArc(rect, start, sweep * fraction, false, p..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.fraction != fraction || old.color != color;
}
