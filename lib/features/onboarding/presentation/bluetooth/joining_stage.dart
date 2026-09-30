import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/status_dot.dart';
import '../../domain/join_status.dart';
import 'bluetooth_setup.dart';
import 'setup_copy.dart';
import 'stage_layout.dart';

enum _Mark { pending, active, done, failed }

/// The board's own report, line by line, while it joins. A failure says
/// what happened and offers the one step that fixes it.
class JoiningStage extends ConsumerWidget {
  const JoiningStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bluetoothSetupProvider);
    final notifier = ref.read(bluetoothSetupProvider.notifier);
    final join = s.join;
    final failed = join is JoinFailed ? join.reason : null;
    final error = s.error;
    final ssid = s.ssid ?? 'the network';
    final copy = failed == null ? null : joinFailureCopy(failed);
    final joined = join is JoinConnected;
    final stuck = error != null && join == null;
    return StageLayout(
      label: '$label · Joining',
      title: copy?.title ?? (stuck ? 'Setup stopped.' : 'Joining $ssid.'),
      emphasis: copy?.emphasis ?? (stuck ? 'stopped' : 'Joining'),
      lead: copy?.body ?? (stuck ? failureCopy(error) : null),
      reduced: reduced,
      children: [
        const _Line('Code accepted', _Mark.done),
        _Line(
          joined ? 'On $ssid at ${join.ip}' : 'Joining $ssid',
          switch (join) {
            _ when stuck => _Mark.failed,
            JoinConnected() => _Mark.done,
            JoinFailed() => _Mark.failed,
            JoinConnecting() => _Mark.active,
            null => _Mark.pending,
          },
        ),
        _Line(
          'Found on your network',
          s.handingOver ? _Mark.active : _Mark.pending,
        ),
        if (copy != null || stuck) ...[
          const SizedBox(height: Space.lg),
          OrionButton(
            label: copy?.action ?? 'Try again',
            trailingArrow: true,
            expand: true,
            isLoading: s.busy,
            onPressed: s.busy ? null : notifier.retry,
          ),
          const SizedBox(height: Space.sm),
          OrionButton.ghost(
            label: 'Choose another network',
            onPressed: s.busy ? null : notifier.back,
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, this.mark);

  final String text;
  final _Mark mark;

  @override
  Widget build(BuildContext context) {
    final lit = mark == _Mark.active || mark == _Mark.done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          StatusDot(
            tone: switch (mark) {
              _Mark.pending => DotTone.off,
              _Mark.active || _Mark.done => DotTone.live,
              _Mark.failed => DotTone.white,
            },
            pulse: mark == _Mark.active,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              text,
              style: context.text.ui.copyWith(
                color: lit ? OrionColors.textWhite : OrionColors.textMuted,
                decoration: mark == _Mark.failed
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
