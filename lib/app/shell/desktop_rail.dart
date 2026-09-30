import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/orion_mark.dart';
import 'connection_badge.dart';
import 'rail_state.dart';
import 'shell_tabs.dart';

/// Left rail for desktop: lockup on top, links, connection at the bottom.
/// Folds to icons only.
class DesktopRail extends ConsumerWidget {
  const DesktopRail({
    super.key,
    required this.location,
    required this.showHarness,
  });

  final String location;
  final bool showHarness;

  static const expandedWidth = 220.0;
  static const collapsedWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(railCollapsedProvider);
    final tabs = [...ShellTabs.desktop, if (showHarness) ShellTabs.harness];
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.uiEase,
      width: collapsed ? collapsedWidth : expandedWidth,
      decoration: const BoxDecoration(
        color: OrionColors.bgSecondary,
        border: Border(right: BorderSide(color: OrionColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md + 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: collapsed
                    ? const OrionMark(size: 28)
                    : const OrionLockup(markSize: 28),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          for (final tab in tabs)
            _RailItem(
              tab: tab,
              active: tab.matches(location),
              collapsed: collapsed,
              onTap: () => context.go(tab.path),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md + 2,
              vertical: Space.md,
            ),
            child: ConnectionBadge(compact: collapsed),
          ),
          _CollapseToggle(
            collapsed: collapsed,
            onTap: ref.read(railCollapsedProvider.notifier).toggle,
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.tab,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final ShellTab tab;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.active || _hovered;
    final color = lit ? OrionColors.textWhite : OrionColors.textMuted;
    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: 1,
                height: 16,
                color: widget.active
                    ? OrionColors.textCyan
                    : Colors.transparent,
              ),
              const SizedBox(width: Space.md + 1),
              Icon(
                widget.active ? widget.tab.activeIcon : widget.tab.icon,
                size: 20,
                color: color,
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: Space.sm),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: Motion.fast,
                    style: context.text.ui.copyWith(
                      color: color,
                      fontSize: 13,
                      letterSpacing: 13 * OrionTracking.ui,
                    ),
                    child: Text(
                      widget.tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!widget.collapsed) return item;
    return Tooltip(message: widget.tab.label, child: item);
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: OrionColors.borderSubtle)),
          ),
          child: Icon(
            collapsed ? Icons.chevron_right : Icons.chevron_left,
            size: 18,
            color: OrionColors.textFaint,
          ),
        ),
      ),
    );
  }
}
