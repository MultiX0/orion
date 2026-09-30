import 'package:flutter/material.dart';

import 'motion.dart';

/// Swaps one step for the next with the same fadeInUp the router uses, so
/// moving inside a screen feels like moving between screens. Key the
/// child by step. With reduced motion the swap is a plain cut.
class StepSwitcher extends StatelessWidget {
  const StepSwitcher({super.key, required this.child, this.reduced = false});

  final Widget child;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.slow,
      reverseDuration: reduced ? Duration.zero : Motion.exit,
      switchInCurve: Motion.uiEase,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: _topAligned,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: reduced ? Offset.zero : const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }

  /// The default layout centers both children; a form and a short step
  /// would jump. Pin them to the top and let the taller one set the size.
  static Widget _topAligned(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    );
  }
}
