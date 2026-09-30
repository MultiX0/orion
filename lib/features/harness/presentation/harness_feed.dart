import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import 'feed_row.dart';

/// A terminal-style feed: a prompt line that says what the PC is
/// doing right now, then one row per call, newest first. A sliver, so the
/// header and the pinned confirmations scroll with it as one column.
class HarnessFeed extends StatelessWidget {
  const HarnessFeed({
    super.key,
    required this.calls,
    this.pendingCount = 0,
    this.reduced = false,
  });

  final List<HarnessCall> calls;
  final int pendingCount;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final running = calls
        .where((c) => c.status == HarnessCallStatus.running)
        .firstOrNull;
    return SliverList.builder(
      itemCount: calls.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return PromptLine(
            text: pendingCount > 0
                ? '$pendingCount waiting for you'
                : running != null
                ? 'running ${running.name}'
                : 'waiting for the board',
            busy: pendingCount > 0 || running != null,
          );
        }
        final call = calls[i - 1];
        final row = FeedRow(key: ValueKey(call.callId), call: call);
        if (reduced) return row;
        return row.animate(
          effects: const [
            FadeEffect(duration: Motion.slow),
            MoveEffect(
              begin: Offset(-20, 0),
              duration: Motion.enter,
              curve: Motion.ease,
            ),
          ],
        );
      },
    );
  }
}

/// A cursor and a short line, like a shell waiting for input.
class PromptLine extends StatelessWidget {
  const PromptLine({super.key, required this.text, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, 0, Space.sm),
      child: Row(
        children: [
          const SizedBox(width: 72, child: _Cursor()),
          AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: context.text.mono.copyWith(
              color: busy ? OrionColors.textCyan : OrionColors.textMuted,
            ),
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

/// A 6x12 block that breathes on the brand's dot pulse. It never blinks
/// hard; nothing in Orion does.
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: OrionMotion.pulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) && _pulse.isAnimating) {
      _pulse.stop();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Opacity(
          opacity: 1 - 0.6 * Curves.easeInOut.transform(_pulse.value),
          child: Container(
            width: 6,
            height: 12,
            decoration: BoxDecoration(
              color: OrionColors.textCyan,
              borderRadius: BorderRadius.circular(OrionRadius.xs),
              boxShadow: const [OrionShadow.glowSm],
            ),
          ),
        ),
      ),
    );
  }
}
