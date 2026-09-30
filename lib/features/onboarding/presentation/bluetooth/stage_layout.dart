import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../step_header.dart';

/// Every Bluetooth station has this shape: the rising header, then its
/// own column. It scrolls on a small phone with the keyboard up.
class StageLayout extends StatelessWidget {
  const StageLayout({
    super.key,
    required this.label,
    required this.title,
    required this.emphasis,
    required this.children,
    this.lead,
    this.reduced = false,
  });

  final String label;
  final String title;
  final String emphasis;
  final String? lead;
  final List<Widget> children;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.form),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ).animate(effects: rise(3, reduced)),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}

/// One line of error copy under a field or a list.
class StageError extends StatelessWidget {
  const StageError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Text(
        message,
        style: context.text.uiSmall.copyWith(color: OrionColors.textWhite),
      ),
    );
  }
}
