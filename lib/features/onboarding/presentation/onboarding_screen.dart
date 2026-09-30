import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/motion/step_switcher.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../../providers/presentation/voice_ui.dart';
import '../data/onboarding_providers.dart';
import 'brain_voice_step.dart';
import 'find_step.dart';
import 'hands_step.dart';
import 'onboarding_frame.dart';
import 'onboarding_notifier.dart';
import 'ready_step.dart';
import 'welcome_step.dart';

/// The journey. Every step but Pair lives here; Pair is its own route so
/// the shared page transition carries the user there and back. When it
/// succeeds the journey resumes at the step after Pair.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider.notifier);
    ref.listen(pairingProvider, (_, next) {
      if (next.value == null) return;
      notifier.afterPairing();
      context.go('/onboarding');
    });
    final ui = ref.watch(onboardingProvider);
    final reduced = isMotionReduced(context, ref);
    final step = ui.step;
    return OnboardingFrame(
      step: step,
      hero: _isHero(step),
      orbMode: _orbMode(ref, step),
      onBack: ui.canGoBack ? notifier.back : null,
      onLater: ui.canSkip ? notifier.next : null,
      child: StepSwitcher(
        reduced: reduced,
        child: KeyedSubtree(
          key: ValueKey(step),
          child: switch (step) {
            OnboardingStep.welcome => WelcomeStep(
              reduced: reduced,
              onFind: notifier.startDiscovery,
            ),
            OnboardingStep.find ||
            OnboardingStep.pair => FindStep(reduced: reduced),
            OnboardingStep.mind => BrainVoiceStep(
              ordinal: ui.ordinal,
              reduced: reduced,
            ),
            OnboardingStep.hands => HandsStep(
              ordinal: ui.ordinal,
              reduced: reduced,
            ),
            OnboardingStep.ready => ReadyStep(
              ordinal: ui.ordinal,
              reduced: reduced,
            ),
          },
        ),
      ),
    );
  }

  static bool _isHero(OnboardingStep step) => switch (step) {
    OnboardingStep.welcome ||
    OnboardingStep.find ||
    OnboardingStep.ready => true,
    _ => false,
  };

  /// What the orb does on each step. Find searches; Voice speaks while a
  /// clip plays; Ready mirrors the board, so it wakes when the link lands.
  static DeviceMode _orbMode(WidgetRef ref, OnboardingStep step) {
    switch (step) {
      case OnboardingStep.find:
        return DeviceMode.thinking;
      case OnboardingStep.mind:
        final playing = ref.watch(voiceUiProvider.select((s) => s.isPlaying));
        return playing ? DeviceMode.speaking : DeviceMode.idle;
      case OnboardingStep.ready:
        return ref.watch(deviceModeProvider);
      case OnboardingStep.welcome:
      case OnboardingStep.pair:
      case OnboardingStep.hands:
        return DeviceMode.idle;
    }
  }
}
