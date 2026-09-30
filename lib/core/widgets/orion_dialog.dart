import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'mono_label.dart';
import 'orion_button.dart';

/// A confirm dialog on the elevated surface, 440 wide, scaleIn entrance.
/// Resolves true when the user confirms.
Future<bool> showOrionDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Keep as is',
  String label = '// Confirm',
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: OrionColors.bgPrimary.withValues(alpha: 0.7),
    transitionDuration: Motion.base,
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.uiEase);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) => _DialogBody(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      label: label,
    ),
  );
  return result ?? false;
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.label,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.form),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Material(
            color: OrionColors.bgCardElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OrionRadius.lg),
              side: const BorderSide(color: OrionColors.borderSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(label),
                  const SizedBox(height: Space.sm),
                  Text(title, style: text.title),
                  const SizedBox(height: Space.sm),
                  Text(body, style: text.body),
                  const SizedBox(height: Space.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OrionButton.ghost(
                        label: cancelLabel,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: Space.sm),
                      OrionButton(
                        label: confirmLabel,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
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
