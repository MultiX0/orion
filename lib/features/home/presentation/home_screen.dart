import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/motion/reduced_motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/status_dot.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../../talk/presentation/hold_to_talk_button.dart';
import 'exchange_bubbles.dart';
import 'live_orb.dart';
import 'mode_copy.dart';
import 'status_strip.dart';

/// Orb in the middle, the last exchange under it, one action, a status
/// strip. Nothing else. The orb takes whatever height is left.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = isMotionReduced(context, ref);
    return Atmosphere(
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: Space.lg),
            const _ModeLine(),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, c) =>
                      LiveOrb(size: min(min(c.maxWidth, c.maxHeight), 400)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: const ExchangeBubbles().animate(
                delay: reduced ? Duration.zero : 300.ms,
                effects: reduced
                    ? const []
                    : const [
                        FadeEffect(duration: Motion.slow),
                        MoveEffect(
                          begin: Offset(0, 18),
                          duration: Motion.slow,
                          curve: Motion.ease,
                        ),
                      ],
              ),
            ),
            const SizedBox(height: Space.lg),
            const HoldToTalkButton(),
            const SizedBox(height: Space.md),
            const StatusStrip(),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
  }
}

class _ModeLine extends ConsumerWidget {
  const _ModeLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(deviceModeProvider);
    final tone = switch (mode) {
      DeviceMode.offline => DotTone.off,
      DeviceMode.error => DotTone.white,
      DeviceMode.idle => DotTone.idle,
      DeviceMode.listening ||
      DeviceMode.thinking ||
      DeviceMode.speaking => DotTone.live,
    };
    return Column(
      children: [
        MonoLabel.eyebrow('Orion · ${modeLabel(mode)}', dotTone: tone),
        const SizedBox(height: Space.xs),
        // Out first, then in, so two serif lines never overlap mid-fade.
        AnimatedSwitcher(
          duration: Motion.base,
          switchOutCurve: const Interval(0.5, 1),
          switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
          child: Text(
            modeCopy(mode),
            key: ValueKey(mode),
            style: context.text.title,
          ),
        ),
      ],
    );
  }
}
