import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_chip.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_dot.dart';
import '../domain/tool_call.dart';
import '../domain/turn_timings.dart';
import '../domain/voice_cues.dart';
import 'expanded_turn.dart';
import 'tool_call_tag.dart';
import 'turn_details.dart';

/// One turn: transcript, reply, tool tags, a muted timing line. Tap to
/// expand. Works for finished turns and the live one alike.
class TurnCard extends ConsumerWidget {
  const TurnCard({
    super.key,
    required this.turnId,
    required this.startedAt,
    this.transcript,
    this.reply,
    this.toolCalls = const [],
    this.timings,
    this.hadImage = false,
    this.isLive = false,
  });

  final String turnId;
  final DateTime? startedAt;
  final String? transcript;
  final String? reply;
  final List<ToolCall> toolCalls;
  final TurnTimings? timings;
  final bool hadImage;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final expanded = ref.watch(
      expandedTurnProvider.select((id) => id == turnId),
    );
    return OrionCard(
      onTap: () => ref.read(expandedTurnProvider.notifier).toggle(turnId),
      selected: isLive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isLive)
                const OrionTag('live', tone: DotTone.live, pulse: true)
              else
                Expanded(
                  child: Text(
                    startedAt == null ? '' : timeAgo(startedAt!).toUpperCase(),
                    style: text.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (isLive) const Spacer(),
              if (hadImage)
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: OrionColors.textFaint,
                ),
              const SizedBox(width: Space.xs),
              Text(turnId, style: text.label),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (transcript != null)
            Text(
              transcript!,
              style: text.body.copyWith(color: OrionColors.textWhite),
            )
          else if (isLive)
            const SizedBox(width: 180, child: SkeletonLines(lines: 1)),
          const SizedBox(height: Space.xs),
          if (reply != null)
            Text(withoutVoiceCues(reply!), style: text.lead)
          else if (isLive)
            const SizedBox(width: 260, child: SkeletonLines(lines: 2)),
          if (toolCalls.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [for (final c in toolCalls) ToolCallTag(c)],
            ),
          ],
          if (timings != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              'stt ${formatMs(timings!.stt)} · '
              'llm ${formatMs(timings!.llm)} · '
              'tts ${formatMs(timings!.ttsFirstByte)} · '
              '${formatMs(timings!.total)}',
              style: text.mono.copyWith(color: OrionColors.textFaint),
            ),
          ],
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.uiEase,
            alignment: Alignment.topCenter,
            child: expanded
                ? TurnDetails(timings: timings, toolCalls: toolCalls)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
