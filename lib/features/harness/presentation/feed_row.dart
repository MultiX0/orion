import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_chip.dart';
import '../../../core/widgets/status_dot.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import 'tool_copy.dart';

/// One call in the feed: clock, name and arguments in the machine voice,
/// the result in body type, a status tag that changes in place. The left
/// edge lights up for a moment whenever the status moves.
class FeedRow extends StatelessWidget {
  const FeedRow({super.key, required this.call});

  final HarnessCall call;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final task = taskOf(call.args);
    final running = call.status == HarnessCallStatus.running;
    return TweenAnimationBuilder<double>(
      key: ValueKey(call.status),
      tween: Tween(begin: 1, end: 0),
      duration: OrionMotion.fade,
      curve: Curves.easeOut,
      builder: (context, flash, child) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: OrionColors.accent.withValues(alpha: 0.6 * flash),
            ),
            bottom: const BorderSide(color: OrionColors.borderSubtle),
          ),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, 0, Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                clock(call.receivedAt),
                style: text.mono.copyWith(color: OrionColors.textFaint),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: call.name,
                          style: text.mono.copyWith(
                            color: OrionColors.textWhite,
                          ),
                        ),
                        if (call.turnId != null)
                          TextSpan(
                            text: '  ·  ${call.turnId}',
                            style: text.mono.copyWith(
                              color: OrionColors.textFaint,
                            ),
                          ),
                        if (call.approvedBy != null)
                          TextSpan(
                            text: '  ·  ${approvedByLabel(call.approvedBy!)}',
                            style: text.mono.copyWith(
                              color: OrionColors.textFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final line in argLines(call.args))
                    Text(line, style: text.mono),
                  if (task != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: Text(
                        task,
                        style: text.bodySmall.copyWith(
                          color: OrionColors.textWhite,
                        ),
                      ),
                    ),
                  if (call.result != null || call.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: Text(
                        '> ${call.result ?? call.message}',
                        style: text.bodySmall.copyWith(
                          color: call.result != null
                              ? OrionColors.textWhite
                              : OrionColors.textMuted,
                        ),
                      ),
                    ),
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: _Elapsed(since: call.receivedAt),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            AnimatedSwitcher(
              duration: Motion.base,
              child: StatusTag(key: ValueKey(call.status), status: call.status),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ticks while a call runs. Driven by a controller, not a timer, so it
/// stops with the widget.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.since});

  final DateTime since;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.text.mono.copyWith(color: OrionColors.textFaint);
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) => Text(
        'running ${elapsedLabel(DateTime.now().difference(widget.since))}',
        style: style,
      ),
    );
  }
}

/// The status as a mono tag. No red or green: waiting and running pulse
/// the accent, done is the accent at rest, error and denied are white.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status});

  final HarnessCallStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone, pulse, accent) = switch (status) {
      HarnessCallStatus.pending => ('pending', DotTone.off, false, false),
      HarnessCallStatus.pendingConfirmation => (
        'waiting',
        DotTone.live,
        true,
        true,
      ),
      HarnessCallStatus.running => ('running', DotTone.live, true, false),
      HarnessCallStatus.done => ('done', DotTone.idle, false, true),
      HarnessCallStatus.error => ('error', DotTone.white, false, false),
      HarnessCallStatus.denied => ('denied', DotTone.white, false, false),
    };
    return OrionTag(label, tone: tone, pulse: pulse, accent: accent);
  }
}
