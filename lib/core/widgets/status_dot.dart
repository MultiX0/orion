import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/tokens.dart';

/// live is the accent with a glow, idle is the accent without one, off is
/// faint, white is for error and denied. The brand has no red or green.
enum DotTone { live, idle, off, white }

/// The 6px indicator dot. pulse runs the brand dotPulse, 2.5 s, forever.
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    this.tone = DotTone.live,
    this.pulse = false,
    this.size = 6,
  });

  final DotTone tone;
  final bool pulse;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: OrionMotion.pulse,
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (widget.pulse) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && _pulse.isAnimating) _pulse.stop();
    final color = switch (widget.tone) {
      DotTone.live || DotTone.idle => OrionColors.textCyan,
      DotTone.off => OrionColors.textFaint,
      DotTone.white => OrionColors.textWhite,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_pulse.value);
        final glow = widget.tone == DotTone.live;
        return Opacity(
          opacity: 1 - 0.5 * t,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: OrionColors.accent.withValues(
                          alpha: 0.5 + 0.3 * t,
                        ),
                        blurRadius: 8 + 8 * t,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}
