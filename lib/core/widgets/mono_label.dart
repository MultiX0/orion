import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'status_dot.dart';

enum MonoRole { label, eyebrow, micro }

/// Machine voice: DM Mono, always uppercase, always tracked. Section labels
/// carry the brand's // marker; pass it in the string.
class MonoLabel extends StatelessWidget {
  const MonoLabel(
    this.text, {
    super.key,
    this.role = MonoRole.label,
    this.color,
    this.live = false,
    this.dotTone = DotTone.live,
    this.textAlign,
  });

  const MonoLabel.eyebrow(
    this.text, {
    super.key,
    this.color,
    this.live = true,
    this.dotTone = DotTone.live,
    this.textAlign,
  }) : role = MonoRole.eyebrow;

  const MonoLabel.micro(this.text, {super.key, this.color, this.textAlign})
    : role = MonoRole.micro,
      live = false,
      dotTone = DotTone.live;

  final String text;
  final MonoRole role;
  final Color? color;
  final bool live;
  final DotTone dotTone;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    var style = switch (role) {
      MonoRole.label => t.label,
      MonoRole.eyebrow => t.eyebrow,
      MonoRole.micro => t.micro,
    };
    if (color != null) style = style.copyWith(color: color);
    final label = Text(
      text.toUpperCase(),
      style: style,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );
    if (!live) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(tone: dotTone, pulse: dotTone == DotTone.live),
        const SizedBox(width: Space.s2 + 2),
        Flexible(child: label),
      ],
    );
  }
}
