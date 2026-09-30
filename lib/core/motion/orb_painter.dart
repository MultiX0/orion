import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme/tokens.dart';
import 'orb_sim.dart';

/// Paints the orb from an OrbSim. Built from light, not paint: layered
/// radial glows, hairline rings, a star-field surface, a bright core.
/// Paints and buffers are reused so a frame allocates only two shaders.
class OrbPainter extends CustomPainter {
  OrbPainter(this.sim, {required super.repaint}) {
    _seedStars();
  }

  final OrbSim sim;

  static const _starCount = 96;
  final _starPolar = Float32List(_starCount * 2);
  final _starBuf = Float32List(_starCount * 2);
  final _haloPaint = Paint();
  final _corePaint = Paint();
  final _dotPaint = Paint();
  final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  final _arcGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final _starPaint = Paint()
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;

  void _seedStars() {
    final rnd = Random(7);
    for (var i = 0; i < _starCount; i++) {
      _starPolar[i * 2] = 0.45 + rnd.nextDouble() * 1.05;
      _starPolar[i * 2 + 1] = rnd.nextDouble() * 2 * pi;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = sim;
    final center = Offset(size.width / 2 + s.shakeX, size.height / 2);
    final base = min(size.width, size.height) / 2 * 0.52;
    final pulse = s.breath + s.level * 0.16 + s.speakPulse * s.breath * 0.6;
    final r = base * s.scale * (1 + pulse);
    final b = s.brightness;
    final tint = _tint(s);

    _haloPaint.shader = ui.Gradient.radial(center, r * 2.4, [
      tint.withValues(alpha: 0.14 * b),
      tint.withValues(alpha: 0),
    ]);
    canvas.drawCircle(center, r * 2.4, _haloPaint);

    _drawStars(canvas, center, base, s, tint);
    _drawRings(canvas, center, r, s, tint);

    final core = Color.lerp(OrionColors.textWhite, tint, 0.35)!;
    _corePaint.shader = ui.Gradient.radial(
      center,
      r,
      [
        core.withValues(alpha: 0.95 * b),
        tint.withValues(alpha: 0.42 * b),
        tint.withValues(alpha: 0.10 * b),
        tint.withValues(alpha: 0),
      ],
      const [0, 0.35, 0.7, 1],
    );
    canvas.drawCircle(center, r, _corePaint);

    _dotPaint.color = OrionColors.textWhite.withValues(alpha: 0.5 + 0.5 * b);
    canvas.drawCircle(center, base * 0.09 * (1 + s.level * 0.5), _dotPaint);

    _drawHighlight(canvas, center, r, s, tint);
  }

  /// Between white-cyan and the accent, pulled toward muted in error.
  Color _tint(OrbSim s) {
    final lit = Color.lerp(
      OrionColors.textCyan,
      OrionColors.textCyanSoft,
      s.accentShift,
    )!;
    return Color.lerp(OrionColors.textMuted, lit, s.saturation)!;
  }

  void _drawStars(
    Canvas canvas,
    Offset center,
    double base,
    OrbSim s,
    Color tint,
  ) {
    if (s.noise <= 0.01) return;
    final drift = s.spinPhase * 0.25;
    final wobble = sin(s.time * 0.7) * 0.03;
    for (var i = 0; i < _starCount; i++) {
      final rr = _starPolar[i * 2] * base * (1 + wobble * (i % 3));
      final a = _starPolar[i * 2 + 1] + drift * (1 + (i % 4) * 0.15);
      _starBuf[i * 2] = center.dx + cos(a) * rr;
      _starBuf[i * 2 + 1] = center.dy + sin(a) * rr;
    }
    final twinkle = 0.55 + 0.45 * sin(s.time * 2.1);
    _starPaint.color = tint.withValues(
      alpha: (0.08 + 0.22 * twinkle) * s.noise * s.brightness,
    );
    canvas.drawRawPoints(ui.PointMode.points, _starBuf, _starPaint);
  }

  void _drawRings(
    Canvas canvas,
    Offset center,
    double r,
    OrbSim s,
    Color tint,
  ) {
    final bloom = s.ringBloom;
    final inner = r * (1.32 + bloom * 0.18 + s.breath * 0.5);
    _ringPaint.color = Color.lerp(
      OrionColors.borderSoft,
      OrionColors.borderCyan,
      bloom,
    )!.withValues(alpha: 0.06 + 0.16 * bloom + 0.06 * s.brightness);
    canvas.drawCircle(center, inner, _ringPaint);
    if (bloom > 0.02) {
      final outer = r * (1.62 + bloom * 0.3 + s.breath);
      _ringPaint.color = tint.withValues(alpha: 0.12 * bloom);
      canvas.drawCircle(center, outer, _ringPaint);
    }
  }

  void _drawHighlight(
    Canvas canvas,
    Offset center,
    double r,
    OrbSim s,
    Color tint,
  ) {
    if (s.highlight <= 0.01) return;
    final rect = Rect.fromCircle(center: center, radius: r * 0.98);
    final sweep = pi / 3 + s.highlight * pi / 4;
    final start = s.spinPhase * 1.4;
    _arcGlowPaint.color = tint.withValues(alpha: 0.35 * s.highlight);
    canvas.drawArc(rect, start, sweep, false, _arcGlowPaint);
    _arcPaint.color = OrionColors.textWhite.withValues(
      alpha: 0.7 * s.highlight,
    );
    canvas.drawArc(rect, start, sweep, false, _arcPaint);
  }

  @override
  bool shouldRepaint(OrbPainter old) => old.sim != sim;
}
