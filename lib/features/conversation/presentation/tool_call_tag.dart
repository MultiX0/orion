import 'package:flutter/material.dart';

import '../../../core/widgets/orion_chip.dart';
import '../../../core/widgets/status_dot.dart';
import '../domain/tool_call.dart';
import '../domain/tool_call_status.dart';

/// A tool call as a mono tag with a status dot. No red or green: pending
/// is faint, running pulses, done is the accent, error is white.
class ToolCallTag extends StatelessWidget {
  const ToolCallTag(this.call, {super.key});

  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final (tone, pulse) = switch (call.status) {
      ToolCallStatus.pending => (DotTone.off, false),
      ToolCallStatus.running => (DotTone.live, true),
      ToolCallStatus.done => (DotTone.idle, false),
      ToolCallStatus.error => (DotTone.white, false),
    };
    return OrionTag(
      call.name.isEmpty ? call.id : call.name,
      tone: tone,
      pulse: pulse,
      accent: call.status == ToolCallStatus.done,
    );
  }
}

/// "1.4s", "480ms". Timings read like an instrument, not a stopwatch.
String formatMs(int? ms) {
  if (ms == null) return '--';
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms}ms';
}

/// "just now", "12 min ago", "3 h ago", else the date.
String timeAgo(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  final d = at.toLocal();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}
