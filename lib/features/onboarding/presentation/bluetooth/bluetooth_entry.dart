import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_card.dart';
import '../../../../core/widgets/orion_chip.dart';

/// On the Find step, the door to a board that is not on the network yet.
class BluetoothEntry extends StatelessWidget {
  const BluetoothEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return OrionCard(
      onTap: () => context.go('/onboarding/bluetooth'),
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_searching,
            size: 24,
            color: OrionColors.accent,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'A new Orion',
                        style: text.title.copyWith(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    const OrionTag('bluetooth', accent: true),
                  ],
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  'Set it up nearby with the code on its screen.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          const Icon(
            Icons.arrow_forward,
            size: 16,
            color: OrionColors.textMuted,
          ),
        ],
      ),
    );
  }
}
