import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mono_label.dart';
import 'shell_tabs.dart';

/// The two destinations that do not fit the phone bar.
Future<void> showMoreSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: OrionColors.bgCardElevated,
    barrierColor: OrionColors.bgPrimary.withValues(alpha: 0.7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(OrionRadius.lg)),
      side: BorderSide(color: OrionColors.borderSoft),
    ),
    builder: (context) => const _MoreSheet(),
  );
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MonoLabel('// More'),
            const SizedBox(height: Space.sm),
            for (final tab in ShellTabs.more)
              _Row(
                tab: tab,
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(tab.path);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.tab, required this.onTap});

  final ShellTab tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            Icon(tab.icon, size: 20, color: OrionColors.textMuted),
            const SizedBox(width: Space.sm),
            Text(tab.label, style: context.text.ui),
            const Spacer(),
            const Icon(
              Icons.arrow_forward,
              size: 16,
              color: OrionColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
