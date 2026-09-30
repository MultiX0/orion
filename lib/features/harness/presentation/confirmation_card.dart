import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/status_dot.dart';
import '../data/harness_providers.dart';
import '../domain/confirmation_request.dart';
import 'tool_copy.dart';

/// A tool waiting for a yes. Says what the tool does, shows every argument
/// and the full task text, and counts down the board's patience.
class ConfirmationCard extends ConsumerWidget {
  const ConfirmationCard({super.key, required this.request, this.onDone});

  final ConfirmationRequest request;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(harnessRepositoryProvider);
    final call = request.toolCall;
    final text = context.text;
    final task = taskOf(call.args);
    final args = argLines(call.args);
    Future<void> answer(Future<void> Function() action) async {
      await action();
      onDone?.call();
    }

    return OrionCard(
      hoverable: false,
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MonoLabel.eyebrow('Waiting for you', dotTone: DotTone.live),
              const Spacer(),
              Text(
                '${call.callId}${call.turnId == null ? '' : ' · ${call.turnId}'}',
                style: text.label,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(call.name, style: text.title.copyWith(fontSize: 20)),
          const SizedBox(height: Space.xxs),
          Text(toolDescription(call.name), style: text.bodySmall),
          if (task != null) ...[
            const SizedBox(height: Space.sm),
            Text(task, style: text.lead.copyWith(color: OrionColors.textWhite)),
          ],
          if (args.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            for (final line in args) Text(line, style: text.mono),
          ],
          const SizedBox(height: Space.md),
          _Deadline(since: request.requestedAt),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OrionButton(
                label: 'Approve',
                onPressed: () => answer(() => repo.approve(request.id)),
              ),
              OrionButton.ghost(
                label: 'Deny',
                onPressed: () => answer(() => repo.deny(request.id)),
              ),
              if (request.canAlwaysAllow)
                OrionButton.secondary(
                  label: 'Always allow this session',
                  onPressed: () => answer(
                    () =>
                        repo.approve(request.id, alwaysAllowThisSession: true),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A hairline that drains over the thirty seconds the board waits, then
/// says so. Approving after that still runs the tool.
class _Deadline extends StatefulWidget {
  const _Deadline({required this.since});

  final DateTime since;

  @override
  State<_Deadline> createState() => _DeadlineState();
}

class _DeadlineState extends State<_Deadline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drain = AnimationController(
    vsync: this,
    duration: boardPatience,
  );

  @override
  void initState() {
    super.initState();
    final gone = DateTime.now().difference(widget.since);
    _drain.value = (gone.inMilliseconds / boardPatience.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    _drain.forward();
  }

  @override
  void dispose() {
    _drain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _drain,
      builder: (context, _) {
        final left = boardPatience * (1 - _drain.value);
        final over = _drain.isCompleted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                const SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: ColoredBox(color: OrionColors.borderSoft),
                ),
                FractionallySizedBox(
                  widthFactor: 1 - _drain.value,
                  child: const SizedBox(
                    height: 1,
                    child: ColoredBox(color: OrionColors.textCyan),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            MonoLabel(
              over
                  ? 'Orion moved on and said so. Approving still runs it'
                  : 'Orion moves on in ${left.inSeconds + 1} s',
              color: over ? OrionColors.textFaint : OrionColors.textMuted,
            ),
          ],
        );
      },
    );
  }
}
