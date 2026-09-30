import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/emphasis_text.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';

/// One line, one button, under the orb waking up. The slow load is
/// deliberate: 0.3 s between arrivals, the brand's hero choreography.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.onFind, this.reduced = false});

  final VoidCallback onFind;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    List<Effect<dynamic>> rise(int step) => reduced
        ? const []
        : [
            FadeEffect(duration: Motion.enter, delay: (step * 300).ms),
            MoveEffect(
              begin: const Offset(0, 40),
              duration: Motion.enter,
              delay: (step * 300).ms,
              curve: Motion.ease,
            ),
          ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.measure),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Space.md),
              const MonoLabel.eyebrow(
                'Orion Protocol · Est. 2026',
              ).animate(effects: rise(1)),
              const SizedBox(height: Space.md),
              EmphasisText(
                'Seek the Undiscovered',
                emphasis: 'Undiscovered',
                style: text.display,
                textAlign: TextAlign.center,
              ).animate(effects: rise(2)),
              const SizedBox(height: Space.md),
              Text(
                'Orion listens on your network. This app finds it, pairs '
                'with it, and stays in touch.',
                style: text.lead,
                textAlign: TextAlign.center,
              ).animate(effects: rise(3)),
              const SizedBox(height: Space.xl),
              OrionButton(
                label: 'Find my Orion',
                trailingArrow: true,
                onPressed: onFind,
              ).animate(effects: rise(4)),
            ],
          ),
        ),
      ),
    );
  }
}
