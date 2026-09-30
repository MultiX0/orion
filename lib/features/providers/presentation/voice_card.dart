import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';

/// The sponsor moment: the chosen voice as a small instrument panel. Bars
/// breathe while a clip plays; otherwise they rest as a hairline.
class VoiceCard extends StatelessWidget {
  const VoiceCard({
    super.key,
    required this.voiceId,
    required this.ttsModel,
    required this.isPlaying,
    required this.isLoading,
    required this.onPreview,
    this.title,
  });

  final String? voiceId;
  final String? title;
  final String ttsModel;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final ready = voiceId != null && voiceId!.isNotEmpty;
    final lit = isPlaying || isLoading;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: OrionColors.bgPrimary,
        border: Border.all(
          color: lit ? OrionColors.borderCyan : OrionColors.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(OrionRadius.card),
        boxShadow: lit ? const [OrionShadow.glowHover] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MonoLabel.eyebrow(
                  isPlaying
                      ? 'Speaking'
                      : isLoading
                      ? 'Fetching the clip'
                      : 'Voice',
                  live: lit,
                ),
              ),
              const SizedBox(width: Space.sm),
              MonoLabel(ttsModel),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            ready ? (title ?? voiceId!) : 'No voice chosen',
            style: text.title.copyWith(fontSize: 20),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (ready && title != null) ...[
            const SizedBox(height: Space.xxs),
            Text(voiceId!, style: text.mono, maxLines: 1),
          ],
          const SizedBox(height: Space.md),
          _Bars(active: isPlaying),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OrionButton.ghost(
                label: isPlaying ? 'Stop' : 'Preview voice',
                icon: isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                isLoading: isLoading,
                onPressed: ready && !isLoading ? onPreview : null,
              ),
              Text(
                ready
                    ? 'Says a line through Fish with this voice.'
                    : 'Pick a voice above to hear it.',
                style: text.uiSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bars extends StatefulWidget {
  const _Bars({required this.active});

  final bool active;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: OrionMotion.reveal,
  );

  static const _count = 28;

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Bars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) {
      _c.animateTo(0, duration: Motion.base);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _count; i++)
              Container(
                width: 2,
                height: 2 + 24 * _height(i),
                decoration: BoxDecoration(
                  color: widget.active
                      ? OrionColors.textCyan
                      : OrionColors.textFaint,
                  borderRadius: BorderRadius.circular(OrionRadius.xs),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A travelling wave, quiet at both ends, zero when idle.
  double _height(int i) {
    if (!widget.active && _c.value == 0) return 0;
    final t = _c.value * 2 * pi;
    final x = i / (_count - 1);
    final envelope = 1 - (2 * x - 1).abs();
    final wave = envelope * (0.55 + 0.45 * sin(t + x * 9));
    return wave.clamp(0.05, 1.0);
  }
}
