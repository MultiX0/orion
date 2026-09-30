import 'dart:math';

import '../../features/device/domain/device_mode.dart';

/// The look of one mode, as numbers the painter can tween between.
/// Transitions are never cut: OrbSim eases every field toward the target.
class OrbLook {
  const OrbLook({
    required this.scale,
    required this.brightness,
    required this.saturation,
    required this.breathRate,
    required this.breathDepth,
    required this.spin,
    required this.accentShift,
    required this.ringBloom,
    required this.highlight,
    required this.noise,
  });

  final double scale;
  final double brightness;
  final double saturation;
  final double breathRate;
  final double breathDepth;
  final double spin;
  final double accentShift;
  final double ringBloom;
  final double highlight;
  final double noise;

  static const offline = OrbLook(
    scale: 0.82,
    brightness: 0.22,
    saturation: 0.15,
    breathRate: 0.1,
    breathDepth: 0.02,
    spin: 0.04,
    accentShift: 0.3,
    ringBloom: 0,
    highlight: 0,
    noise: 0.1,
  );

  static const idle = OrbLook(
    scale: 1,
    brightness: 0.7,
    saturation: 1,
    breathRate: 0.22,
    breathDepth: 0.04,
    spin: 0.12,
    accentShift: 0.55,
    ringBloom: 0,
    highlight: 0.15,
    noise: 0.5,
  );

  static const listening = OrbLook(
    scale: 1.14,
    brightness: 1,
    saturation: 1,
    breathRate: 0.6,
    breathDepth: 0.05,
    spin: 0.3,
    accentShift: 0.5,
    ringBloom: 0.45,
    highlight: 0.25,
    noise: 0.7,
  );

  static const thinking = OrbLook(
    scale: 1,
    brightness: 0.85,
    saturation: 1,
    breathRate: 0.4,
    breathDepth: 0.03,
    spin: 1.8,
    accentShift: 1,
    ringBloom: 0.1,
    highlight: 1,
    noise: 1,
  );

  static const speaking = OrbLook(
    scale: 1.06,
    brightness: 0.95,
    saturation: 1,
    breathRate: 1.5,
    breathDepth: 0.07,
    spin: 0.5,
    accentShift: 0.7,
    ringBloom: 1,
    highlight: 0.35,
    noise: 0.6,
  );

  static const error = OrbLook(
    scale: 0.96,
    brightness: 0.6,
    saturation: 0.35,
    breathRate: 0.22,
    breathDepth: 0.03,
    spin: 0.12,
    accentShift: 0.2,
    ringBloom: 0,
    highlight: 0,
    noise: 0.3,
  );

  static OrbLook forMode(DeviceMode mode) => switch (mode) {
    DeviceMode.offline => offline,
    DeviceMode.idle => idle,
    DeviceMode.listening => listening,
    DeviceMode.thinking => thinking,
    DeviceMode.speaking => speaking,
    DeviceMode.error => error,
  };
}

/// Runs the orb's numbers forward in time. Pure Dart, no allocation per
/// tick, so the painter can read it every frame.
class OrbSim {
  OrbSim({OrbLook start = OrbLook.offline}) : target = start {
    _snap(start);
  }

  OrbLook target;
  bool reduced = false;

  double scale = 1;
  double brightness = 0;
  double saturation = 0;
  double breathRate = 0;
  double breathDepth = 0;
  double spin = 0;
  double accentShift = 0;
  double ringBloom = 0;
  double highlight = 0;
  double noise = 0;
  double level = 0;
  double speakPulse = 0;

  double breathPhase = 0;
  double spinPhase = 0;
  double time = 0;
  double _shakeT = 10;
  double _levelTarget = 0;
  var _speaking = false;

  /// Per second. The mock's shortest phase, listening, lasts 600 ms; at
  /// this rate the orb is 97% of the way there before the next event.
  static const _ease = 6.0;

  void setMode(DeviceMode mode) {
    final next = OrbLook.forMode(mode);
    if (mode == DeviceMode.error && !identical(target, next)) _shakeT = 0;
    target = next;
  }

  void setLevel(double? value) => _levelTarget = (value ?? 0).clamp(0, 1);

  void setSpeaking(bool value) => _speaking = value;

  void tick(double dt) {
    final k = 1 - exp(-dt * _ease);
    scale += (target.scale - scale) * k;
    brightness += (target.brightness - brightness) * k;
    saturation += (target.saturation - saturation) * k;
    breathRate += (target.breathRate - breathRate) * k;
    breathDepth += (target.breathDepth - breathDepth) * k;
    spin += (target.spin - spin) * k;
    accentShift += (target.accentShift - accentShift) * k;
    ringBloom += (target.ringBloom - ringBloom) * k;
    highlight += (target.highlight - highlight) * k;
    noise += (target.noise - noise) * k;
    level += (_levelTarget - level) * min(1, dt * 12);
    speakPulse += ((_speaking ? 1 : 0) - speakPulse) * k;

    // Reduced motion slows the orb down, it never stops.
    final speed = reduced ? 0.3 : 1.0;
    time += dt * speed;
    breathPhase += dt * speed * breathRate * 2 * pi;
    spinPhase += dt * speed * spin;
    _shakeT += dt;
  }

  double get breath => sin(breathPhase) * breathDepth;

  /// Short horizontal shake on entering error, then nothing.
  double get shakeX =>
      _shakeT > 0.7 || reduced ? 0 : sin(_shakeT * 42) * exp(-_shakeT * 6) * 7;

  void _snap(OrbLook look) {
    scale = look.scale;
    brightness = look.brightness;
    saturation = look.saturation;
    breathRate = look.breathRate;
    breathDepth = look.breathDepth;
    spin = look.spin;
    accentShift = look.accentShift;
    ringBloom = look.ringBloom;
    highlight = look.highlight;
    noise = look.noise;
  }
}
