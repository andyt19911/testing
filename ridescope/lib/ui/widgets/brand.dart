import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// "RideScope" wordmark: condensed type with a gradient "Scope".
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final style = TextStyle(fontFamily: AppTheme.display, fontWeight: FontWeight.w800, fontSize: size, height: 1, letterSpacing: 0.2);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size * 0.32,
        height: size * 0.32,
        margin: EdgeInsets.only(right: size * 0.28, bottom: size * 0.04),
        decoration: BoxDecoration(gradient: rs.signature, shape: BoxShape.circle),
      ),
      Text('Ride', style: style.copyWith(color: rs.text)),
      ShaderMask(
        shaderCallback: (b) => rs.signature.createShader(b),
        child: Text('Scope', style: style.copyWith(color: Colors.white)),
      ),
    ]);
  }
}

/// A simple, original side-profile motorcycle drawn from primitives (two
/// wheels, a swept tank/seat line and forks). Used as decoration, not a logo.
class MotorcycleGlyph extends CustomPainter {
  MotorcycleGlyph({required this.color, this.strokeWidth = 3});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width, h = size.height;
    final r = min(w, h) * 0.17; // wheel radius
    final y = h * 0.74; // axle line
    final rearC = Offset(w * 0.2, y);
    final frontC = Offset(w * 0.82, y);

    canvas.drawCircle(rearC, r, p);
    canvas.drawCircle(frontC, r, p);
    // hubs
    final hub = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(rearC, strokeWidth * 0.7, hub);
    canvas.drawCircle(frontC, strokeWidth * 0.7, hub);

    // body line: rear wheel -> seat -> tank -> headstock
    final body = Path()
      ..moveTo(rearC.dx, rearC.dy)
      ..lineTo(w * 0.3, y - r * 1.1)
      ..lineTo(w * 0.42, y - r * 2.4) // seat hump
      ..quadraticBezierTo(w * 0.55, y - r * 3.0, w * 0.64, y - r * 2.2) // tank
      ..lineTo(w * 0.7, y - r * 2.0);
    canvas.drawPath(body, p);

    // front forks + bars
    canvas.drawLine(Offset(w * 0.7, y - r * 2.0), frontC, p);
    canvas.drawLine(Offset(w * 0.7, y - r * 2.0), Offset(w * 0.78, y - r * 3.1), p); // bars

    // underbody to rear
    canvas.drawLine(Offset(w * 0.42, y - r * 0.2), Offset(w * 0.64, y - r * 0.2), p);
    canvas.drawLine(Offset(w * 0.42, y - r * 0.2), Offset(w * 0.42, y - r * 2.4), p);
  }

  @override
  bool shouldRepaint(MotorcycleGlyph old) => old.color != color || old.strokeWidth != strokeWidth;
}
