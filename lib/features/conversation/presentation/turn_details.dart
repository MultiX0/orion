import 'package:flutter/material.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/mono_label.dart';
import '../domain/tool_call.dart';
import '../domain/turn_timings.dart';
import 'tool_call_tag.dart';

/// The expanded part of a turn card: a timing breakdown and the raw
/// arguments and results of each tool call.
class TurnDetails extends StatelessWidget {
  const TurnDetails({super.key, this.timings, this.toolCalls = const []});

  final TurnTimings? timings;
  final List<ToolCall> toolCalls;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.md),
        const Hairline(),
        const SizedBox(height: Space.md),
        const MonoLabel('// Timings'),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            _Metric('stt', timings?.stt),
            _Metric('llm', timings?.llm),
            _Metric('tts', timings?.ttsFirstByte),
            _Metric('total', timings?.total),
          ],
        ),
        for (final call in toolCalls) ...[
          const SizedBox(height: Space.md),
          Row(
            children: [
              ToolCallTag(call),
              const SizedBox(width: Space.xs),
              Text(call.id, style: text.mono),
            ],
          ),
          const SizedBox(height: Space.xs),
          _Raw(label: 'args', value: call.args.toString()),
          if (call.result != null) ...[
            const SizedBox(height: Space.xs),
            _Raw(label: 'result', value: call.result!),
          ],
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.ms);

  final String label;
  final int? ms;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatMs(ms),
            style: text.metric.copyWith(fontSize: 22, letterSpacing: -0.4),
          ),
          const SizedBox(height: Space.xxs),
          MonoLabel.micro(label),
        ],
      ),
    );
  }
}

class _Raw extends StatelessWidget {
  const _Raw({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: OrionColors.bgPrimary,
        border: Border.all(color: OrionColors.borderSubtle),
        borderRadius: BorderRadius.circular(OrionRadius.sm),
      ),
      child: Text('$label: $value', style: context.text.mono),
    );
  }
}
