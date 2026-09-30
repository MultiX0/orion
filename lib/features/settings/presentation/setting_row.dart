import 'package:flutter/material.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';

/// Label and a line of help on the left, the control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    required this.child,
    this.help,
  });

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.ui),
                if (help != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(help!, style: text.uiSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          child,
        ],
      ),
    );
  }
}

/// A read-only fact: Playfair value over a mono caption.
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: text.metric.copyWith(fontSize: 20, letterSpacing: -0.4),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xxs),
        Text(label.toUpperCase(), style: text.micro),
      ],
    );
  }
}
