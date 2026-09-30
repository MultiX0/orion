import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/tokens.dart';

/// A 36x20 toggle. On: highlight track, accent border, glowing thumb.
/// Off: card track, subtle border, muted thumb. State lives in a provider.
class OrionSwitch extends StatelessWidget {
  const OrionSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      label: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: AnimatedOpacity(
            duration: Motion.fast,
            opacity: enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Curves.easeOut,
              width: 36,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? OrionColors.bgHighlight : OrionColors.bgCard,
                border: Border.all(
                  color: value
                      ? OrionColors.borderCyan
                      : OrionColors.borderSubtle,
                ),
                borderRadius: BorderRadius.circular(OrionRadius.full),
              ),
              child: AnimatedAlign(
                duration: Motion.fast,
                curve: Motion.uiEase,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: value ? OrionColors.textCyan : OrionColors.textMuted,
                    shape: BoxShape.circle,
                    boxShadow: value ? const [OrionShadow.glowSm] : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Material's slider with every default stripped: a 2px track, a small
/// glowing thumb, no overlay, no value bubble.
class OrionSlider extends StatelessWidget {
  const OrionSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 100,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: const SliderThemeData(
        trackHeight: 2,
        activeTrackColor: OrionColors.textCyan,
        inactiveTrackColor: OrionColors.borderSoft,
        thumbColor: OrionColors.textCyan,
        overlayColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: 6,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
        trackShape: RectangularSliderTrackShape(),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
