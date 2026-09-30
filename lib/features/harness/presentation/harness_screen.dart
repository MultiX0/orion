import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/harness_providers.dart';
import 'confirmation_card.dart';
import 'harness_feed.dart';
import 'harness_header.dart';

/// Desktop only. Status on top, confirmations pinned, then the feed, all
/// in one scrolling column so a stack of confirmations never hides it.
class HarnessScreen extends ConsumerWidget {
  const HarnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(harnessFeedProvider);
    final pending = ref.watch(pendingConfirmationsProvider).value ?? const [];
    final enabled = ref.watch(
      harnessStatusProvider.select((s) => s.value?.isEnabled ?? false),
    );
    final reduced = isMotionReduced(context, ref);
    final count = feed.value?.length ?? 0;
    return SafeArea(
      child: Column(
        children: [
          const OrionAppBar(
            label: '// Harness',
            title: 'Orion at the keyboard',
            emphasis: 'keyboard',
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OrionContainer.narrow,
                ),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      sliver: SliverList.list(
                        children: [
                          const HarnessHeader(),
                          if (enabled)
                            for (final request in pending) ...[
                              const SizedBox(height: Space.md),
                              ConfirmationCard(request: request),
                            ],
                          const SizedBox(height: Space.lg),
                          Row(
                            children: [
                              const MonoLabel('// Feed'),
                              const Spacer(),
                              Text(
                                (count == 1
                                        ? '1 call this session'
                                        : '$count calls this session')
                                    .toUpperCase(),
                                style: context.text.label,
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.sm),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.lg,
                        0,
                        Space.lg,
                        Space.xl,
                      ),
                      sliver: switch (feed) {
                        _ when !enabled => const _Quiet(handsOff: true),
                        AsyncData(:final value) when value.isEmpty =>
                          const _Quiet(),
                        AsyncData(:final value) => HarnessFeed(
                          calls: value,
                          pendingCount: pending.length,
                          reduced: reduced,
                        ),
                        AsyncError(:final error) => SliverToBoxAdapter(
                          child: EmptyState(
                            label: '// Error',
                            title: 'The feed stopped',
                            emphasis: 'stopped',
                            body: '$error',
                          ),
                        ),
                        _ => const SliverToBoxAdapter(
                          child: SkeletonLines(lines: 4),
                        ),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The feed with nothing in it: hands off, or simply quiet so far.
class _Quiet extends StatelessWidget {
  const _Quiet({this.handsOff = false});

  final bool handsOff;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!handsOff) const PromptLine(text: 'waiting for the board'),
          const SizedBox(height: Space.xl),
          handsOff
              ? const EmptyState(
                  label: '// Hands off',
                  title: 'Orion keeps its hands to itself',
                  emphasis: 'itself',
                  body:
                      'The tool server is stopped and the board is not '
                      'offered any PC tools. Flip PC control above to '
                      'change that.',
                )
              : const EmptyState(
                  label: '// Quiet',
                  title: 'No calls yet',
                  emphasis: 'yet',
                  body:
                      'When Orion asks this PC to do something, it shows up '
                      'here as it happens.',
                ),
        ],
      ),
    );
  }
}
