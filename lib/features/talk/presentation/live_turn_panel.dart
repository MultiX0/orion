import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../conversation/data/live_turn_notifier.dart';
import '../../conversation/domain/voice_cues.dart';
import '../../conversation/presentation/tool_call_tag.dart';

/// Transcript and reply for the turn in flight, then the last one until
/// a new turn starts. Each line surfaces as its socket event lands.
class LiveTurnPanel extends ConsumerWidget {
  const LiveTurnPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(liveTurnProvider);
    final text = context.text;
    if (turn == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Text(
          'Your words and the reply will appear here.',
          style: text.body,
          textAlign: TextAlign.center,
        ),
      );
    }
    final running = !turn.isDone;
    return OrionCard(
      hoverable: false,
      selected: running,
      child: AnimatedSize(
        duration: Motion.base,
        curve: Motion.uiEase,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: MonoLabel.eyebrow(
                    running ? 'Turn in flight' : 'Last turn',
                    live: running,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(turn.turnId, style: text.label),
              ],
            ),
            const SizedBox(height: Space.md),
            const MonoLabel('// You said'),
            const SizedBox(height: Space.xxs),
            if (turn.transcript != null)
              Text(
                turn.transcript!,
                style: text.body.copyWith(color: OrionColors.textWhite),
              )
            else
              const SizedBox(width: 200, child: SkeletonLines(lines: 1)),
            const SizedBox(height: Space.md),
            const MonoLabel('// Orion'),
            const SizedBox(height: Space.xxs),
            if (turn.reply != null)
              Text(withoutVoiceCues(turn.reply!), style: text.lead)
            else
              const SizedBox(width: 280, child: SkeletonLines(lines: 2)),
            if (turn.toolCalls.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [for (final c in turn.toolCalls) ToolCallTag(c)],
              ),
            ],
            if (turn.timings != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                'total ${formatMs(turn.timings!.total)} · '
                'llm ${formatMs(turn.timings!.llm)}',
                style: text.mono.copyWith(color: OrionColors.textFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
