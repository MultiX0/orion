import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/tokens.dart';

/// The brand card: bg card, subtle 1px border, 12px radius. Hover lifts the
/// surface one step and softens the border. selected uses the one blue-cast
/// surface the brand allows, so use it sparingly.
class OrionCard extends StatefulWidget {
  const OrionCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.large = false,
    this.selected = false,
    this.hoverable = true,
    this.clip = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool large;
  final bool selected;
  final bool hoverable;
  final bool clip;

  @override
  State<OrionCard> createState() => _OrionCardState();
}

class _OrionCardState extends State<OrionCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.hoverable && _hovered;
    final radius = BorderRadius.circular(
      widget.large ? OrionRadius.lg : OrionRadius.card,
    );
    final color = widget.selected
        ? OrionColors.bgHighlight
        : lit
        ? OrionColors.bgCardElevated
        : OrionColors.bgCard;
    final border = widget.selected
        ? OrionColors.borderCyan
        : lit
        ? OrionColors.borderSoft
        : OrionColors.borderSubtle;
    final body = AnimatedContainer(
      duration: Motion.base,
      curve: Motion.uiEase,
      padding:
          widget.padding ?? EdgeInsets.all(widget.large ? Space.xl : Space.lg),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border),
        borderRadius: radius,
      ),
      clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
      child: widget.child,
    );
    if (widget.onTap == null && !widget.hoverable) return body;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: body,
      ),
    );
  }
}
