import 'dart:async';

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'mono_label.dart';

OverlayEntry? _current;
Timer? _timer;

/// A line at the bottom of the screen that surfaces, waits, and fades.
/// Never a key, never an error a screen should own; a fact worth a glance,
/// like a path something was saved to.
void showOrionToast(
  BuildContext context, {
  required String message,
  String label = '// Done',
  bool mono = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dismiss();
  final entry = OverlayEntry(
    builder: (_) => _Toast(label: label, message: message, mono: mono),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 3500), _dismiss);
}

void _dismiss() {
  _timer?.cancel();
  _timer = null;
  _current?.remove();
  _current = null;
}

class _Toast extends StatelessWidget {
  const _Toast({
    required this.label,
    required this.message,
    required this.mono,
  });

  final String label;
  final String message;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: Space.lg,
      right: Space.lg,
      bottom: Space.xxl + Space.lg,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduced ? 1 : 0, end: 1),
            duration: Motion.slow,
            curve: Motion.ease,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - v)),
                child: child,
              ),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: OrionContainer.form),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: OrionColors.bgCardElevated,
                border: Border.all(color: OrionColors.borderSoft),
                borderRadius: BorderRadius.circular(OrionRadius.btn),
                boxShadow: const [OrionShadow.glowHover],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(label),
                  const SizedBox(height: Space.xxs),
                  Text(
                    message,
                    style: mono
                        ? text.mono.copyWith(color: OrionColors.textWhite)
                        : text.ui,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
