import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/reduced_motion.dart';
import '../../data/onboarding_providers.dart';
import '../onboarding_frame.dart';
import '../onboarding_notifier.dart';
import 'bluetooth_setup.dart';
import 'bluetooth_setup_flow.dart';

/// Pair, the Bluetooth way. Wears the journey's frame as the third star.
/// Brain and voice is asked here, before the Wi-Fi, so the journey drops
/// its own copy. Continue records the board like any pairing, and
/// OnboardingScreen underneath moves the journey on past Pair.
class BluetoothPairScreen extends ConsumerWidget {
  const BluetoothPairScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orb = ref.watch(bluetoothSetupProvider.select(setupOrbMode));
    final stage = ref.watch(bluetoothSetupProvider.select((s) => s.stage));
    final notifier = ref.read(bluetoothSetupProvider.notifier);
    final reduced = isMotionReduced(context, ref);
    return OnboardingFrame(
      step: OnboardingStep.pair,
      hero: stage == SetupStage.nearby || stage == SetupStage.done,
      orbMode: orb,
      onBack: switch (stage) {
        SetupStage.nearby => () => context.go('/onboarding'),
        SetupStage.done => null,
        _ => notifier.back,
      },
      child: BluetoothSetupFlow(
        label: '// 03 · Pair',
        reduced: reduced,
        onDone: (device) {
          ref.read(onboardingProvider.notifier).keysAskedDuringPairing();
          ref.read(pairingProvider.notifier).adopt(device);
        },
      ),
    );
  }
}
