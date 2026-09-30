import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_info.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../data/conversation_providers.dart';
import '../data/live_turn_notifier.dart';
import '../domain/turn.dart';
import 'turn_card.dart';

/// Newest first. The live turn sits on top before history knows about it.
/// Pull to refresh on phones, a refresh button on desktop.
class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turns = ref.watch(turnsProvider);
    final isDesktop = ref.watch(platformInfoProvider).isDesktop;
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    final loading = turns.isLoading && !turns.hasValue;
    // A fetch that failed while the board was away is retried on relink.
    ref.listen(deviceModeProvider, (prev, next) {
      if (prev == DeviceMode.offline && next != DeviceMode.offline) {
        ref.invalidate(turnsProvider);
      }
    });
    return SafeArea(
      child: Column(
        children: [
          OrionAppBar(
            label: '// Conversation',
            title: 'Every turn',
            emphasis: 'turn',
            actions: [
              if (isDesktop)
                OrionButton.ghost(
                  label: 'Refresh',
                  size: OrionButtonSize.compact,
                  icon: Icons.refresh,
                  isLoading: loading,
                  onPressed: () => ref.invalidate(turnsProvider),
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator.noSpinner(
              onRefresh: () async {
                ref.invalidate(turnsProvider);
                await ref.read(turnsProvider.future);
              },
              child: switch (turns) {
                AsyncData(:final value) => _List(turns: value),
                // History lives on the board. With no link the fetch hangs
                // or fails, and neither deserves a spinner or a stack trace.
                _ when offline => const _List(turns: []),
                AsyncError(:final error) => _Error(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(turnsProvider),
                ),
                _ => const _Loading(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.turns});

  final List<Turn> turns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveTurnProvider);
    final showLive = live != null && !live.isDone;
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    if (turns.isEmpty && !showLive) {
      return EmptyState(
        label: offline ? '// Offline' : '// Empty',
        title: offline ? 'Orion is out of reach' : 'Nothing charted yet',
        emphasis: offline ? 'reach' : 'charted',
        body: offline
            ? 'History lives on the board. It will fill in when the link returns.'
            : 'Say the wake word, or open Talk and type a question.',
      );
    }
    final count = turns.length + (showLive ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        0,
        Space.lg,
        Space.xxl + Space.lg,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        if (showLive && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TurnCard(
              turnId: live.turnId,
              startedAt: live.startedAt,
              transcript: live.transcript,
              reply: live.reply,
              toolCalls: live.toolCalls,
              timings: live.timings,
              isLive: true,
            ),
          );
        }
        final t = turns[showLive ? i - 1 : i];
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: TurnCard(
            turnId: t.id,
            startedAt: t.startedAt,
            transcript: t.transcript,
            reply: t.reply,
            toolCalls: t.toolCalls,
            timings: t.timingsMs,
            hadImage: t.hadImage,
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      children: const [
        Skeleton.card(),
        SizedBox(height: Space.sm),
        Skeleton.card(),
        SizedBox(height: Space.sm),
        Skeleton.card(),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      label: '// Error',
      title: 'History did not load',
      emphasis: 'load',
      body: message,
      action: OrionButton.ghost(label: 'Try again', onPressed: onRetry),
    );
  }
}
