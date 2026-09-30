import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'mono_label.dart';

/// Looks like the brand input, acts like a button: it shows the chosen
/// value and opens a picker on tap, Enter or Space.
class OrionSelectField extends StatefulWidget {
  const OrionSelectField({
    super.key,
    required this.onTap,
    this.value,
    this.label,
    this.placeholder = 'Choose',
    this.mono = false,
  });

  final VoidCallback? onTap;
  final String? value;
  final String? label;
  final String placeholder;
  final bool mono;

  @override
  State<OrionSelectField> createState() => _OrionSelectFieldState();
}

class _OrionSelectFieldState extends State<OrionSelectField> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final value = widget.value;
    final style = widget.mono
        ? text.mono.copyWith(fontSize: OrionFontSize.ui)
        : text.ui;
    final border = _focused
        ? OrionColors.borderCyan
        : _hovered
        ? OrionColors.borderSoft
        : OrionColors.borderSubtle;
    final enabled = widget.onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          MonoLabel(widget.label!),
          const SizedBox(height: Space.xs),
        ],
        FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowHoverHighlight: (on) => setState(() => _hovered = on),
          onShowFocusHighlight: (on) => setState(() => _focused = on),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.uiEase,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: OrionColors.bgCard,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(OrionRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? widget.placeholder,
                      style: style.copyWith(
                        color: value == null
                            ? OrionColors.textFaint
                            : OrionColors.textWhite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Icon(
                    Icons.unfold_more,
                    size: 18,
                    color: _hovered || _focused
                        ? OrionColors.textWhite
                        : OrionColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
