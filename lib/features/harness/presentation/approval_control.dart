import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_chip.dart';
import '../../../core/widgets/status_dot.dart';
import 'approval_choice.dart';

/// Off, Ask me first, Act on your own. The same control everywhere the
/// choice can be made: the Hands step as three cards, Settings and the
/// Harness header as a dense row with the chosen sentence under it.
class ApprovalControl extends ConsumerWidget {
  const ApprovalControl({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(approvalChoiceProvider);
    final setting = ref.watch(approvalSetterProvider);
    final setter = ref.read(approvalSetterProvider.notifier);
    final text = context.text;
    final shown = setting.busy ?? choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dense)
          _DenseRow(
            shown: shown,
            busy: setting.busy != null,
            onPick: setter.set,
          )
        else
          for (final c in ApprovalChoice.values) ...[
            _ChoiceCard(
              choice: c,
              selected: c == shown,
              busy: setting.busy != null,
              onTap: () => setter.set(c),
            ),
            if (c != ApprovalChoice.values.last)
              const SizedBox(height: Space.sm),
          ],
        if (setting.error != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            setting.error!,
            style: text.uiSmall.copyWith(color: OrionColors.textWhite),
          ),
        ],
      ],
    );
  }
}

class _DenseRow extends StatelessWidget {
  const _DenseRow({
    required this.shown,
    required this.busy,
    required this.onPick,
  });

  final ApprovalChoice shown;
  final bool busy;
  final ValueChanged<ApprovalChoice> onPick;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final c in ApprovalChoice.values)
              OrionChip(
                label: c.title,
                selected: c == shown,
                onTap: busy ? null : () => onPick(c),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        // A keyed fade-in, not a switcher: a choice that bounces twice
        // inside one fade must never stack the same key.
        TweenAnimationBuilder<double>(
          key: ValueKey(shown),
          tween: Tween(begin: 0, end: 1),
          duration: Motion.base,
          curve: Curves.easeOut,
          builder: (context, v, child) => Opacity(opacity: v, child: child),
          child: Text(shown.sentence, style: text.uiSmall),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.choice,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final ApprovalChoice choice;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final index = (choice.index + 1).toString().padLeft(2, '0');
    return OrionCard(
      selected: selected,
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(index, style: text.label),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  choice.title,
                  style: text.title.copyWith(
                    fontSize: 20,
                    color: selected
                        ? OrionColors.textWhite
                        : OrionColors.textMuted,
                  ),
                ),
                const SizedBox(height: Space.xxs),
                Text(choice.sentence, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: StatusDot(
              tone: selected ? DotTone.live : DotTone.off,
              pulse: selected && busy,
            ),
          ),
        ],
      ),
    );
  }
}
