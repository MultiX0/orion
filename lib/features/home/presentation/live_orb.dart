import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/orb.dart';
import '../../../core/motion/reduced_motion.dart';
import '../../conversation/data/live_turn_notifier.dart';
import '../../device/data/device_state_notifier.dart';

/// The orb wired to the board. Watches mode, mic level and tts state each
/// through select, so an RSSI tick never touches it.
class LiveOrb extends ConsumerWidget {
  const LiveOrb({super.key, this.size = 260});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(deviceModeProvider);
    final level = ref.watch(deviceStateProvider.select((s) => s.level));
    final speaking = ref.watch(
      liveTurnProvider.select((t) => t?.isSpeaking ?? false),
    );
    return Orb(
      mode: mode,
      level: level,
      isSpeaking: speaking,
      reducedMotion: isMotionReduced(context, ref),
      size: size,
    );
  }
}
