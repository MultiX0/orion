import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';

/// The progress line: one four-pointed star per step, joined by a hairline
/// that fills as the user moves. The current star is lit and breathes.
/// Everything is tweened, so a step change is a glide, never a jump.
class Constellation extends StatelessWidget {
  const Constellation({
    super.key,
    required this.labels,
    required this.index,
    this.reduced = false,
  });

  final List<String> labels;
  final int index;
  final bool reduced;

  /// Below this many pixels per step the labels would touch.
  static const _labelColumnMin = 64.0;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: index.toDouble()),
      duration: reduced ? Duration.zero : Motion.enter,
      curve: Motion.ease,
      builder: (context, progress, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: Space.lg,
            child: _Stars(
              count: labels.length,
              progress: progress,
              reduced: reduced,
            ),
          ),
          const SizedBox(height: Space.xxs),
          // A phone has no room for seven labels, so it names the current
          // step only, under the lit star.
          LayoutBuilder(
            builder: (context, constraints) {
              final column = constraints.maxWidth / labels.length;
              if (column < _labelColumnMin) {
                return Text(
                  labels[index].toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: text.micro.copyWith(color: OrionColors.textCyanSoft),
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: Motion.base,
                        style: text.micro.copyWith(
                          color: i == index
                              ? OrionColors.textCyanSoft
                              : i < index
                              ? OrionColors.textMuted
                              : OrionColors.textFaint,
                        ),
                        child: Text(
                          labels[i].toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatefulWidget {
  const _Stars({
    required this.count,
    required this.progress,
    required this.reduced,
  });

  final int count;
  final double progress;
  final bool reduced;

  @override
  State<_Stars> createState() => _StarsState();
}

class _StarsState extends State<_Stars> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: OrionMotion.pulse,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduced) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarsPainter(
        count: widget.count,
        progress: widget.progress,
        pulse: _pulse,
      ),
      size: Size.infinite,
    );
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter({
    required this.count,
    required this.progress,
    required this.pulse,
  }) : super(repaint: pulse);

  final int count;
  final double progress;
  final Animation<double> pulse;

  static const _lit = OrionColors.textCyan;
  static const _past = OrionColors.textCyanSoft;
  static const _ahead = OrionColors.textFaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final cy = size.height / 2;
    final column = size.width / count;
    double x(double i) => column * (i + 0.5);

    // The unlit path first, then the travelled part over it.
    final line = Paint()
      ..strokeWidth = 1
      ..color = OrionColors.borderSoft;
    canvas.drawLine(Offset(x(0), cy), Offset(x(count - 1.0), cy), line);
    line.color = _past.withValues(alpha: 0.7);
    canvas.drawLine(Offset(x(0), cy), Offset(x(progress), cy), line);

    final breath = Curves.easeInOut.transform(pulse.value);
    for (var i = 0; i < count; i++) {
      // How lit this star is: 1 at the current step, fading over one step.
      final lit = (1 - (progress - i).abs()).clamp(0.0, 1.0);
      final past = i < progress;
      final base = past ? _past : _ahead;
      final color = Color.lerp(base, _lit, lit)!;
      final radius = 3.0 + 2.5 * lit;
      final center = Offset(x(i.toDouble()), cy);
      if (lit > 0) {
        canvas.drawCircle(
          center,
          radius * 2.2,
          Paint()
            ..color = OrionColors.accent.withValues(
              alpha: lit * (0.25 + 0.25 * breath),
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawPath(_star(center, radius), Paint()..color = color);
    }
  }

  /// The brand's navigational star: four points, concave arms.
  static Path _star(Offset c, double r) {
    final inner = r * 0.2;
    final path = Path()..moveTo(c.dx, c.dy - r);
    for (var k = 0; k < 4; k++) {
      final a = -pi / 2 + k * pi / 2;
      final mid = a + pi / 4;
      path
        ..lineTo(c.dx + inner * cos(mid), c.dy + inner * sin(mid))
        ..lineTo(c.dx + r * cos(mid + pi / 4), c.dy + r * sin(mid + pi / 4));
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_StarsPainter old) =>
      old.count != count || old.progress != progress;
}
