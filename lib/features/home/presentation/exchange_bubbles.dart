import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/skeleton.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../data/home_providers.dart';

/// The last exchange as two short bubbles. Each slides in when its text
/// arrives over the socket; a live turn shows a breathing placeholder.
/// The box reserves room for both bubbles at full length, so the orb above
/// never moves when a reply lands.
class ExchangeBubbles extends ConsumerWidget {
  const ExchangeBubbles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exchange = ref.watch(lastExchangeProvider);
    final transcript = exchange.transcript;
    final reply = exchange.reply;
    final empty = transcript == null && reply == null && !exchange.isLive;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: OrionContainer.measure,
        minHeight: 168,
      ),
      child: AnimatedSwitcher(
        duration: Motion.base,
        switchInCurve: Motion.ease,
        child: empty
            ? const _Hint()
            : Column(
                key: ValueKey('$transcript|$reply|${exchange.isLive}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Bubble(text: transcript, mine: true, live: exchange.isLive),
                  const SizedBox(height: Space.xs),
                  _Bubble(text: reply, mine: false, live: exchange.isLive),
                ],
              ),
      ),
    );
  }
}

class _Hint extends ConsumerWidget {
  const _Hint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Text(
        offline
            ? 'Orion is out of reach. The app keeps looking and links up '
                  'on its own.'
            : 'Say the wake word, or hold the button below.',
        style: context.text.body,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, required this.live});

  final String? text;
  final bool mine;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    if (text == null && !live) return const SizedBox.shrink();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.slow,
        curve: Motion.ease,
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - v)),
            child: child,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: mine ? OrionColors.bgCard : Colors.transparent,
            border: Border.all(
              color: mine ? OrionColors.borderSubtle : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(OrionRadius.card),
          ),
          child: text == null
              ? const SizedBox(width: 160, child: SkeletonLines(lines: 1))
              : Text(
                  text!,
                  style: mine
                      ? t.body.copyWith(color: OrionColors.textWhite)
                      : t.lead.copyWith(
                          fontSize: 17,
                          color: OrionColors.textWhite,
                        ),
                  textAlign: mine ? TextAlign.right : TextAlign.left,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ),
    );
  }
}
