import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/orion_button.dart';
import '../../device/domain/device_mode.dart';
import 'constellation.dart';
import 'onboarding_notifier.dart';
import 'step_orb.dart';

/// The chrome around every step: the constellation on top, the orb under
/// it, back and later at the edges. The body slots in below and scrolls
/// on its own. The pair page wears this too, so it reads as one journey.
class OnboardingFrame extends ConsumerWidget {
  const OnboardingFrame({
    super.key,
    required this.step,
    required this.orbMode,
    required this.child,
    this.hero = false,
    this.onBack,
    this.onLater,
  });

  final OnboardingStep step;
  final DeviceMode orbMode;
  final Widget child;
  final bool hero;
  final VoidCallback? onBack;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(onboardingProvider.select((s) => s.steps));
    final reduced = isMotionReduced(context, ref);
    return Scaffold(
      backgroundColor: OrionColors.bgPrimary,
      body: Atmosphere(
        grid: true,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.md,
                  Space.md,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Edge(
                      child: onBack == null
                          ? null
                          : OrionButton.ghost(
                              label: 'Back',
                              size: OrionButtonSize.compact,
                              icon: Icons.arrow_back,
                              onPressed: onBack,
                            ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                        ),
                        child: Constellation(
                          labels: [for (final s in steps) s.label],
                          index: steps.indexOf(step),
                          reduced: reduced,
                        ),
                      ),
                    ),
                    _Edge(
                      alignEnd: true,
                      child: onLater == null
                          ? null
                          : OrionButton.secondary(
                              label: 'Later',
                              onPressed: onLater,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              StepOrb(mode: orbMode, hero: hero, reduced: reduced),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Same width on both sides so the constellation stays centered.
class _Edge extends StatelessWidget {
  const _Edge({this.child, this.alignEnd = false});

  final Widget? child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    // Wide enough for the compact Back button with its arrow.
    return SizedBox(
      width: 100,
      height: 36,
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
