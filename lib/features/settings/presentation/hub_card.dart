import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_dialog.dart';
import '../../../core/widgets/orion_toast.dart';
import '../data/hub_notifier.dart';
import '../domain/hub_status.dart';
import 'setting_row.dart';

/// Orion Hub: a home server that answers the board's turns with an agent
/// that can act on the network (hub/README.md). The board finds hubs and
/// pairs itself; this card starts it and shows how it went.
class HubCard extends ConsumerWidget {
  const HubCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final status = ref.watch(hubStatusProvider);
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// Hub'),
          const SizedBox(height: Space.xs),
          Text('Orion Hub', style: text.title),
          const SizedBox(height: Space.sm),
          Text(
            'A home server Orion thinks on. It can check your network, '
            'Docker and other machines, and remembers across turns.',
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          switch (status) {
            AsyncData(:final value) => _Body(status: value),
            // Only a 404 means firmware from before hubs.
            AsyncError(:final error) when error is NotFoundFailure => Text(
              'This board does not know about hubs yet. Update its firmware.',
              style: text.bodySmall,
            ),
            AsyncError(:final error) => Text(
              error is Failure
                  ? error.message
                  : 'Could not ask the board about hubs.',
              style: text.bodySmall,
            ),
            _ => const SizedBox(height: 40),
          },
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.status});

  final HubStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final notifier = ref.read(hubStatusProvider.notifier);
    final s = status;
    final line = switch (s.state) {
      'scanning' => 'Looking for hubs on this network...',
      'found' =>
        s.found.length == 1
            ? 'Found one hub.'
            : 'Found ${s.found.length} hubs.',
      'pairing' => 'Asking the hub...',
      'waiting' =>
        'Waiting for the hub owner to approve this board. Code ${s.code ?? '--'}. '
            'On the hub: docker exec orion-hub orion-hub-cli approve '
            '${s.code ?? '<code>'}',
      'connected' => 'Connected. Turns go to the hub first.',
      'offline' => 'Paired, but the hub does not answer right now.',
      'failed' => 'That did not work: ${s.message ?? 'unknown reason'}.',
      _ => 'No hub found yet.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line, style: text.body),
        if (s.paired || s.name != null) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.xl,
            runSpacing: Space.md,
            children: [
              if (s.name != null) FactTile(label: 'hub', value: s.name!),
              if (s.address != null)
                FactTile(label: 'address', value: s.address!),
            ],
          ),
        ],
        if (!s.paired &&
            s.found.isNotEmpty &&
            s.state != 'pairing' &&
            s.state != 'waiting') ...[
          const SizedBox(height: Space.md),
          for (final h in s.found)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${h.name}  ${h.url.replaceFirst('http://', '')}',
                      style: text.uiSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  OrionButton.secondary(
                    label: 'Connect',
                    onPressed: () => _run(context, notifier.connect(h.url)),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            if (!s.paired)
              OrionButton.ghost(
                label: s.busy ? 'Working...' : 'Look for hubs',
                icon: Icons.search,
                onPressed: s.busy ? null : () => _run(context, notifier.scan()),
              ),
            if (s.paired)
              OrionButton.ghost(
                label: 'Disconnect from the hub',
                icon: Icons.link_off,
                onPressed: () => _forget(context, ref),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, Future<Object?> action) async {
    final result = await action;
    if (!context.mounted) return;
    if (result case Err(:final failure)) {
      showOrionToast(context, label: '// Hub', message: failure.message);
    }
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await showOrionDialog(
      context,
      title: 'Disconnect from the hub?',
      body:
          'Orion goes back to answering on its own, or on this PC or phone. '
          'You can pair with the hub again any time.',
      confirmLabel: 'Disconnect',
    );
    if (ok) await ref.read(hubStatusProvider.notifier).forget();
  }
}
