import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import 'more_sheet.dart';
import 'shell_tabs.dart';

/// Bottom nav for phones: four tabs plus More, blurred over the page.
class MobileNavBar extends StatelessWidget {
  const MobileNavBar({super.key, required this.location});

  final String location;

  static const _scrim = Color.fromRGBO(9, 9, 11, 0.72);

  @override
  Widget build(BuildContext context) {
    const tabs = ShellTabs.mobile;
    final moreActive = ShellTabs.more.any((t) => t.matches(location));
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: const BoxDecoration(
            color: _scrim,
            border: Border(top: BorderSide(color: OrionColors.borderSubtle)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final tab in tabs)
                    Expanded(
                      child: _NavItem(
                        label: tab.label,
                        icon: tab.icon,
                        activeIcon: tab.activeIcon,
                        active: tab.matches(location),
                        onTap: () => context.go(tab.path),
                      ),
                    ),
                  Expanded(
                    child: _NavItem(
                      label: 'More',
                      icon: Icons.more_horiz,
                      activeIcon: Icons.more_horiz,
                      active: moreActive,
                      onTap: () => showMoreSheet(context),
                    ),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? OrionColors.textWhite : OrionColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: Motion.fast,
            child: Icon(
              active ? activeIcon : icon,
              key: ValueKey(active),
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(height: Space.s1),
          AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: context.text.uiSmall.copyWith(
              color: color,
              fontSize: 11,
              letterSpacing: 11 * OrionTracking.ui,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
