import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/emphasis_text.dart';
import '../../../core/widgets/mono_label.dart';

/// Label, title with one italic word, a line of lead. The three rise in
/// one after another, the brand's stagger, unless motion is reduced.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.label,
    required this.title,
    this.emphasis,
    this.lead,
    this.centered = false,
    this.reduced = false,
  });

  final String label;
  final String title;
  final String? emphasis;
  final String? lead;
  final bool centered;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        MonoLabel(label, textAlign: align).animate(effects: rise(0, reduced)),
        const SizedBox(height: Space.sm),
        EmphasisText(
          title,
          emphasis: emphasis,
          style: text.headline,
          textAlign: align,
        ).animate(effects: rise(1, reduced)),
        if (lead != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            lead!,
            style: text.lead,
            textAlign: align,
          ).animate(effects: rise(2, reduced)),
        ],
      ],
    );
  }
}

/// Fade and rise, delayed by one stagger per position. Nothing when reduced.
List<Effect<dynamic>> rise(int position, bool reduced) => reduced
    ? const []
    : [
        FadeEffect(duration: Motion.slow, delay: Motion.stagger * position),
        MoveEffect(
          begin: const Offset(0, 18),
          duration: Motion.slow,
          delay: Motion.stagger * position,
          curve: Motion.ease,
        ),
      ];
