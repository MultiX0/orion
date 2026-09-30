import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// The one transition every route uses: the brand's fadeInUp. The router
/// calls these and nothing else, so tuning happens here only.
Page<void> orionPage({required GoRouterState state, required Widget child}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.exit,
    transitionsBuilder: _fadeUp,
  );
}

/// The pages inside the shell: a short fade, nothing else. The 700 ms fade
/// and slide above keeps both pages built and composited the whole way, which
/// makes tab switches on the PC slow and drops frames.
Page<void> orionTabPage({required GoRouterState state, required Widget child}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.fast,
    reverseTransitionDuration: const Duration(milliseconds: 120),
    transitionsBuilder: _fade,
  );
}

Widget _fade(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

/// A translucent page over the current one, for confirmations. scaleIn.
Page<void> orionModalPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    opaque: false,
    barrierDismissible: true,
    barrierColor: OrionColors.bgPrimary.withValues(alpha: 0.7),
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.exit,
    transitionsBuilder: _scaleIn,
  );
}

Widget _fadeUp(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final curved = CurvedAnimation(parent: animation, curve: Motion.uiEase);
  final offset = Tween(
    begin: reduced ? Offset.zero : const Offset(0, 0.03),
    end: Offset.zero,
  ).animate(curved);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(position: offset, child: child),
  );
}

Widget _scaleIn(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: Motion.uiEase);
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween(begin: 0.97, end: 1.0).animate(curved),
      child: child,
    ),
  );
}
