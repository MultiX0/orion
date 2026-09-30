import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_button.dart';
import 'step_header.dart';

/// Brain, Voice and Hands share this shape: a header, the form, and one
/// Continue at the end. The form scrolls; the header rises in first.
class FormStep extends StatelessWidget {
  const FormStep({
    super.key,
    required this.label,
    required this.title,
    required this.emphasis,
    required this.lead,
    required this.onContinue,
    required this.child,
    this.continueLabel = 'Continue',
    this.reduced = false,
  });

  final String label;
  final String title;
  final String emphasis;
  final String lead;
  final VoidCallback onContinue;
  final Widget child;
  final String continueLabel;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.article),
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            StepHeader(
              label: label,
              title: title,
              emphasis: emphasis,
              lead: lead,
              reduced: reduced,
            ),
            const SizedBox(height: Space.lg),
            child.animate(effects: rise(3, reduced)),
            const SizedBox(height: Space.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OrionButton(
                  label: continueLabel,
                  trailingArrow: true,
                  onPressed: onContinue,
                ),
              ],
            ).animate(effects: rise(4, reduced)),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}
