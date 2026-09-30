import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/motion/orb.dart';
import '../../device/domain/device_mode.dart';

/// The orb that rides along the whole journey. One instance lives above
/// the steps, so its mode and size glide between them instead of a new
/// orb appearing on each. Hero steps get the big one.
class StepOrb extends StatelessWidget {
  const StepOrb({
    super.key,
    required this.mode,
    required this.hero,
    this.reduced = false,
  });

  final DeviceMode mode;
  final bool hero;
  final bool reduced;

  static const heroSize = 200.0;
  static const compactSize = 88.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: hero ? heroSize : compactSize),
      duration: reduced ? Duration.zero : Motion.enter,
      curve: Motion.ease,
      builder: (context, size, _) =>
          Orb(mode: mode, reducedMotion: reduced, size: size),
    );
  }
}
