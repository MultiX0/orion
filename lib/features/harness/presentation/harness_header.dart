import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_dot.dart';
import '../data/harness_providers.dart';
import '../domain/harness_status.dart';
import 'approval_control.dart';

/// The three-way choice, then server, agent runtime and the brain the
/// harness mirrors.
class HarnessHeader extends ConsumerWidget {
  const HarnessHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(harnessStatusProvider);
    return OrionCard(
      hoverable: false,
      child: switch (status) {
        AsyncData(:final value) => _Header(status: value),
        AsyncError(:final error) => _Header(
          status: const HarnessStatus(),
          error: '$error',
        ),
        _ => const SkeletonLines(lines: 3),
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.status, this.error});

  final HarnessStatus status;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final s = status;
    final runtime = s.isDshAvailable
        ? [
            'dsh ${s.dshVersion ?? ''}',
            if (s.nodeVersion != null) 'node ${s.nodeVersion}',
          ].join(' · ').trim()
        : s.nodeVersion != null
        ? 'node ${s.nodeVersion} · no dsh'
        : 'not found';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MonoLabel('// PC control'),
        const SizedBox(height: Space.xs),
        Text(s.isEnabled ? 'Hands on this PC' : 'Hands off', style: text.title),
        if (error != null) ...[
          const SizedBox(height: Space.xs),
          Text(error!, style: text.body),
        ],
        const SizedBox(height: Space.md),
        const ApprovalControl(dense: true),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.xl,
          runSpacing: Space.md,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _Stat(
              label: 'Tool server',
              value: s.isServerRunning
                  ? s.serverAddress ?? 'listening'
                  : 'stopped',
              tone: s.isServerRunning ? DotTone.live : DotTone.off,
            ),
            _Stat(
              label: 'Agent runtime',
              value: runtime,
              hint: s.isDshAvailable
                  ? null
                  : s.nodeVersion != null
                  ? 'Node 22.19 or newer plus dsh enable agent tasks.'
                  : 'Install Node 22.19 or newer to enable agent tasks.',
              tone: s.isDshAvailable ? DotTone.idle : DotTone.off,
            ),
            _Stat(
              label: 'Brain',
              value: s.model == null
                  ? 'none mirrored'
                  : '${s.providerName ?? ''} · ${s.model}',
              hint: s.model == null
                  ? 'Pick a model under Providers and it mirrors here.'
                  : null,
              tone: s.model == null ? DotTone.off : DotTone.idle,
              action: OrionButton.secondary(
                label: s.model == null ? 'Pick one' : 'Change',
                onPressed: () => context.go('/providers'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    this.hint,
    this.action,
  });

  final String label;
  final String value;
  final DotTone tone;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MonoLabel.micro(label),
        const SizedBox(height: Space.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(tone: tone, pulse: tone == DotTone.live),
            const SizedBox(width: Space.xs),
            Text(
              value,
              style: text.mono.copyWith(color: OrionColors.textWhite),
            ),
            if (action != null) ...[const SizedBox(width: Space.sm), action!],
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: Space.xxs),
          Text(hint!, style: text.uiSmall),
        ],
      ],
    );
  }
}
