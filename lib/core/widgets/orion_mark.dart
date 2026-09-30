import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The mark: one four-point star, traced from brand/assets/logo.png. Always
/// white on dark; the accent only ever appears around it as glow.
class OrionMark extends StatelessWidget {
  const OrionMark({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color ?? OrionColors.textWhite),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  /// The star on the logo's own 256 grid: tips 2 px inside the edge, the
  /// waist 25.6 px from the center, straight edges between them.
  static final _star = Path()
    ..moveTo(128, 2)
    ..lineTo(153.6, 102.4)
    ..lineTo(254, 128)
    ..lineTo(153.6, 153.6)
    ..lineTo(128, 254)
    ..lineTo(102.4, 153.6)
    ..lineTo(2, 128)
    ..lineTo(102.4, 102.4)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 256);
    canvas.drawPath(_star, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Playfair wordmark, last syllable italic, no period inline.
class OrionWordmark extends StatelessWidget {
  const OrionWordmark({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = context.text.title.copyWith(
      fontSize: fontSize,
      letterSpacing: fontSize * OrionTracking.tight,
      height: 1,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: const [
          TextSpan(text: 'Ori'),
          TextSpan(
            text: 'on',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// Mark plus wordmark, 12px apart, as in the nav.
class OrionLockup extends StatelessWidget {
  const OrionLockup({super.key, this.markSize = 28});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionMark(size: markSize),
        const SizedBox(width: Space.sm),
        OrionWordmark(fontSize: markSize * 0.7),
      ],
    );
  }
}
