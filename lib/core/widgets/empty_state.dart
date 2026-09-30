import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'emphasis_text.dart';
import 'mono_label.dart';

/// Empty, offline and error states share one shape: label, title with one
/// italic word, a line of body, and at most one action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.label,
    required this.title,
    this.emphasis,
    this.body,
    this.action,
    this.leading,
  });

  final String label;
  final String title;
  final String? emphasis;
  final String? body;
  final Widget? action;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.form),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(height: Space.lg),
              ],
              MonoLabel(label, textAlign: TextAlign.center),
              const SizedBox(height: Space.sm),
              EmphasisText(
                title,
                emphasis: emphasis,
                style: text.title,
                textAlign: TextAlign.center,
              ),
              if (body != null) ...[
                const SizedBox(height: Space.sm),
                Text(body!, style: text.body, textAlign: TextAlign.center),
              ],
              if (action != null) ...[
                const SizedBox(height: Space.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
