import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'status_dot.dart';

enum OrionButtonVariant { primary, secondary, ghost }

enum OrionButtonSize { standard, compact }

/// The three brand buttons. Primary is a 10% accent wash with a 20% border,
/// never a solid fill. Secondary is a bare link with a sweeping underline.
class OrionButton extends StatefulWidget {
  const OrionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OrionButtonVariant.primary,
    this.size = OrionButtonSize.standard,
    this.icon,
    this.trailingArrow = false,
    this.isLoading = false,
    this.expand = false,
  });

  const OrionButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingArrow = false,
    this.isLoading = false,
  }) : variant = OrionButtonVariant.secondary,
       size = OrionButtonSize.standard,
       expand = false;

  const OrionButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = OrionButtonSize.standard,
    this.icon,
    this.trailingArrow = false,
    this.isLoading = false,
    this.expand = false,
  }) : variant = OrionButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final OrionButtonVariant variant;
  final OrionButtonSize size;
  final IconData? icon;
  final bool trailingArrow;
  final bool isLoading;
  final bool expand;

  @override
  State<OrionButton> createState() => _OrionButtonState();
}

class _OrionButtonState extends State<OrionButton> {
  var _hovered = false;
  var _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final lit = _enabled && (_hovered || _pressed);
    final child = widget.variant == OrionButtonVariant.secondary
        ? _SecondaryBody(widget: widget, lit: lit)
        : _FilledBody(widget: widget, lit: lit);
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedOpacity(
          duration: Motion.fast,
          opacity: _enabled || widget.isLoading ? 1 : 0.45,
          child: child,
        ),
      ),
    );
  }
}

class _FilledBody extends StatelessWidget {
  const _FilledBody({required this.widget, required this.lit});

  final OrionButton widget;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final primary = widget.variant == OrionButtonVariant.primary;
    final compact = widget.size == OrionButtonSize.compact;
    final fill = primary
        ? OrionColors.accent.withValues(alpha: lit ? 0.18 : OrionAlpha.fill)
        : Colors.transparent;
    final border = primary
        ? OrionColors.accent.withValues(
            alpha: lit ? OrionAlpha.borderHover : OrionAlpha.border,
          )
        : (lit ? OrionColors.borderSoft : OrionColors.borderSubtle);
    final textColor = primary || lit
        ? OrionColors.textWhite
        : OrionColors.textMuted;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, lit && primary ? -1 : 0, 0),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.s3 + 2 : Space.lg,
        vertical: compact ? Space.s2 + 2 : Space.sm,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(OrionRadius.btn),
        boxShadow: lit && primary ? const [OrionShadow.glowHover] : null,
      ),
      child: _Label(widget: widget, color: textColor, lit: lit),
    );
  }
}

class _SecondaryBody extends StatelessWidget {
  const _SecondaryBody({required this.widget, required this.lit});

  final OrionButton widget;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final color = lit ? OrionColors.textWhite : OrionColors.textMuted;
    // The stack takes the label's width; the underline sweeps by scaling
    // from the left edge, so it needs no fractional sizing.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: _Label(
            widget: widget,
            color: color,
            lit: lit,
            weightRegular: true,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedContainer(
            duration: Motion.hover,
            curve: Curves.easeOut,
            height: 1,
            transformAlignment: Alignment.centerLeft,
            transform: Matrix4.diagonal3Values(lit ? 1 : 0.001, 1, 1),
            color: OrionColors.textCyan,
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.widget,
    required this.color,
    required this.lit,
    this.weightRegular = false,
  });

  final OrionButton widget;
  final Color color;
  final bool lit;
  final bool weightRegular;

  @override
  Widget build(BuildContext context) {
    final style = (weightRegular ? context.text.ui : context.text.button)
        .copyWith(color: color);
    return Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          const StatusDot(tone: DotTone.live, pulse: true),
          const SizedBox(width: Space.s2 + 2),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: color),
          const SizedBox(width: Space.s2 + 2),
        ],
        Flexible(child: Text(widget.label, style: style, maxLines: 1)),
        if (widget.trailingArrow) ...[
          const SizedBox(width: Space.s2 + 2),
          AnimatedSlide(
            duration: Motion.hover,
            curve: Curves.easeOut,
            offset: Offset(lit ? 0.2 : 0, 0),
            child: Icon(Icons.arrow_forward, size: 16, color: color),
          ),
        ],
      ],
    );
  }
}
