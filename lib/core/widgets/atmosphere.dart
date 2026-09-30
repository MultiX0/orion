import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// The recurring background treatment from brand/colors.md: a cool haze
/// top left, a fainter warm one bottom right, an optional dot grid.
/// Put it behind a screen; it never captures pointer events.
class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key, this.grid = false, this.child});

  final bool grid;
  final Widget? child;

  static const _coolHaze = Color.fromRGBO(30, 60, 100, 0.10);
  static const _warmHaze = Color.fromRGBO(40, 80, 70, 0.06);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (grid) const CustomPaint(painter: _DotGridPainter()),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.9, -0.9),
                    radius: 1.1,
                    colors: [_coolHaze, Colors.transparent],
                    stops: [0, 0.7],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, 0.9),
                    radius: 1,
                    colors: [_warmHaze, Colors.transparent],
                    stops: [0, 0.7],
                  ),
                ),
              ),
            ],
          ),
        ),
        ?child,
      ],
    );
  }
}

/// The cartographic dot grid, 32px pitch, 1px accent dots at 10%.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const _pitch = 32.0;
  static const _dot = Color.fromRGBO(160, 210, 230, 0.10);

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / _pitch).ceil() + 1;
    final rows = (size.height / _pitch).ceil() + 1;
    final points = Float32List(cols * rows * 2);
    var i = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        points[i++] = c * _pitch;
        points[i++] = r * _pitch;
      }
    }
    canvas.drawRawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = _dot
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}

/// A hairline that fades at both ends, for under section headers.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.accent = false});

  final bool accent;

  static const _white = Color.fromRGBO(255, 255, 255, 0.08);
  static const _cyan = Color.fromRGBO(124, 184, 206, 0.6);

  @override
  Widget build(BuildContext context) {
    final mid = accent ? _cyan : _white;
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, mid, Colors.transparent],
          ),
        ),
      ),
    );
  }
}
