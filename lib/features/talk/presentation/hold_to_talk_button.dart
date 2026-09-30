import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/status_dot.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../data/talk_notifier.dart';

/// The one primary action. Press starts a turn as if the wake word fired;
/// the board decides when you stopped talking, so release does nothing.
/// While the board is busy, a tap interrupts it.
class HoldToTalkButton extends ConsumerWidget {
  const HoldToTalkButton({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(deviceModeProvider);
    final sending = ref.watch(talkProvider.select((t) => t.isSending));
    final busy = switch (mode) {
      DeviceMode.listening ||
      DeviceMode.thinking ||
      DeviceMode.speaking => true,
      DeviceMode.idle || DeviceMode.error || DeviceMode.offline => false,
    };
    final offline = mode == DeviceMode.offline;
    final lit = busy || sending;
    final label = offline
        ? 'Orion is offline'
        : busy
        ? 'Tap to interrupt'
        : 'Hold to talk';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: offline ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: offline
                ? null
                : (_) {
                    final talk = ref.read(talkProvider.notifier);
                    busy ? talk.stop() : talk.startListening();
                  },
            child: AnimatedContainer(
              duration: Motion.hover,
              curve: Motion.uiEase,
              width: size * (lit ? 1.08 : 1),
              height: size * (lit ? 1.08 : 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OrionColors.accent.withValues(
                  alpha: lit ? 0.18 : OrionAlpha.fill,
                ),
                border: Border.all(
                  color: OrionColors.accent.withValues(
                    alpha: offline
                        ? OrionAlpha.fill
                        : lit
                        ? OrionAlpha.borderHover
                        : OrionAlpha.border,
                  ),
                ),
                boxShadow: lit ? const [OrionShadow.glowHover] : null,
              ),
              child: Icon(
                busy ? Icons.stop_rounded : Icons.mic_none,
                size: size * 0.36,
                color: offline ? OrionColors.textFaint : OrionColors.textWhite,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        MonoLabel(
          label,
          role: MonoRole.eyebrow,
          color: offline ? OrionColors.textFaint : null,
          live: lit,
          dotTone: lit ? DotTone.live : DotTone.off,
        ),
      ],
    );
  }
}
