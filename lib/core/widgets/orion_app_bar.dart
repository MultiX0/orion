import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'emphasis_text.dart';
import 'mono_label.dart';

/// Screen header: a mono section label over a Playfair title, actions on
/// the right. It is a plain row, not a Material AppBar.
class OrionAppBar extends StatelessWidget {
  const OrionAppBar({
    super.key,
    required this.title,
    this.label,
    this.emphasis,
    this.actions = const [],
    this.showBack = false,
    this.padding,
  });

  final String title;
  final String? label;
  final String? emphasis;
  final List<Widget> actions;
  final bool showBack;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            _BackButton(onTap: () => _back(context)),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  MonoLabel(label!),
                  const SizedBox(height: Space.xs),
                ],
                EmphasisText(
                  title,
                  emphasis: emphasis,
                  style: text.headline,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: Space.sm),
            action,
          ],
        ],
      ),
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: Space.xl + Space.s2,
          height: Space.xl + Space.s2,
          decoration: BoxDecoration(
            border: Border.all(color: OrionColors.borderSubtle),
            borderRadius: BorderRadius.circular(OrionRadius.btn),
          ),
          child: const Icon(Icons.arrow_back, size: 18),
        ),
      ),
    );
  }
}
