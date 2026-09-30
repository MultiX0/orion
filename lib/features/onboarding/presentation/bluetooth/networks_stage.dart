import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/mono_label.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/orion_card.dart';
import '../../domain/board_network.dart';
import 'bluetooth_setup.dart';
import 'setup_copy.dart';
import 'signal_bars.dart';
import 'stage_layout.dart';

/// What the board can hear from where it stands, strongest first, with a
/// lock on the ones that want a password and a way to name a hidden one.
class NetworksStage extends ConsumerWidget {
  const NetworksStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networks = ref.watch(
      bluetoothSetupProvider.select((s) => s.networks),
    );
    final loaded = ref.watch(
      bluetoothSetupProvider.select((s) => s.networksLoaded),
    );
    final busy = ref.watch(bluetoothSetupProvider.select((s) => s.busy));
    final error = ref.watch(bluetoothSetupProvider.select((s) => s.error));
    final notifier = ref.read(bluetoothSetupProvider.notifier);
    return StageLayout(
      label: '$label · Network',
      title: 'Choose its network.',
      emphasis: 'network',
      lead:
          'The board scanned for itself. It reaches 2.4 GHz only, so a '
          '5 GHz network will not be here.',
      reduced: reduced,
      children: [
        MonoLabel.eyebrow(
          busy
              ? 'The board is scanning'
              : (loaded ? '${networks.length} heard' : 'Waiting for the board'),
          live: busy,
        ),
        const SizedBox(height: Space.md),
        if (error != null) StageError(failureCopy(error)),
        if (loaded && networks.isEmpty && !busy)
          Text(
            'The board heard no networks. Move it closer to the router and '
            'scan again.',
            style: context.text.bodySmall,
          ),
        for (final network in networks) ...[
          NetworkRow(
            key: ValueKey(network.ssid),
            network: network,
            onTap: busy ? null : () => notifier.chooseNetwork(network),
          ),
          const SizedBox(height: Space.xs),
        ],
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            OrionButton.secondary(
              label: 'Hidden network',
              onPressed: busy ? null : notifier.chooseHidden,
            ),
            OrionButton.ghost(
              label: 'Scan again',
              icon: Icons.refresh,
              onPressed: busy ? null : notifier.loadNetworks,
            ),
          ],
        ),
      ],
    );
  }
}

class NetworkRow extends StatelessWidget {
  const NetworkRow({super.key, required this.network, this.onTap});

  final BoardNetwork network;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OrionCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          SignalBars(bars: network.bars),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              network.ssid,
              style: context.text.ui.copyWith(color: OrionColors.textWhite),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (network.secured)
            const Icon(
              Icons.lock_outline,
              size: 14,
              color: OrionColors.textMuted,
              semanticLabel: 'Needs a password',
            ),
          const SizedBox(width: Space.sm),
          const Icon(
            Icons.arrow_forward,
            size: 16,
            color: OrionColors.textMuted,
          ),
        ],
      ),
    );
  }
}
