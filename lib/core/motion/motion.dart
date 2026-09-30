import '../theme/tokens.dart';

/// Shared timings, named by role. Values come from brand/motion.md.
abstract final class Motion {
  static const fast = OrionMotion.fast;
  static const hover = OrionMotion.hover;
  static const base = OrionMotion.med;
  static const slow = OrionMotion.keyframe;
  static const enter = OrionMotion.reveal;
  static const exit = OrionMotion.fast;
  static const stagger = OrionMotion.stagger;

  /// The signature curve: very fast start, long settle.
  static const ease = OrionMotion.easeBrand;
  static const uiEase = OrionMotion.easeUi;
}
