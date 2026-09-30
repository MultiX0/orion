import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_chip.dart';
import '../../../core/widgets/orion_mark.dart';
import '../../../core/widgets/status_dot.dart';
import '../../device/domain/device.dart';

/// One found board: name, address, firmware, and how it was found as a
/// mono tag (beacon, mdns, sweep, name). Surfaces out of the dark when
/// discovery confirms it.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
    this.reduced = false,
  });

  final Device device;
  final VoidCallback onTap;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final source = device.source;
    final card = OrionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const OrionMark(size: 28),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        style: text.title.copyWith(fontSize: 20),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source != null && source.isNotEmpty) ...[
                      const SizedBox(width: Space.xs),
                      OrionTag(source, accent: source == 'beacon'),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  '${device.host}'
                  '${device.fwVersion == null ? '' : ' · fw ${device.fwVersion}'}',
                  style: text.mono,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          const StatusDot(tone: DotTone.live),
          const SizedBox(width: Space.sm),
          const Icon(
            Icons.arrow_forward,
            size: 16,
            color: OrionColors.textMuted,
          ),
        ],
      ),
    );
    if (reduced) return card;
    return card.animate(
      effects: const [
        FadeEffect(duration: Motion.slow),
        MoveEffect(
          begin: Offset(0, 18),
          duration: Motion.slow,
          curve: Motion.ease,
        ),
      ],
    );
  }
}
