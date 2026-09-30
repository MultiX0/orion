import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/mono_label.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/orion_card.dart';
import '../../../../core/widgets/orion_chip.dart';
import '../../../../core/widgets/orion_mark.dart';
import '../../domain/board_network.dart';
import '../../domain/nearby_board.dart';
import 'bluetooth_setup.dart';
import 'setup_copy.dart';
import 'signal_bars.dart';
import 'stage_layout.dart';

/// Boards in setup mode surface as the radio hears them, strongest first.
class NearbyStage extends ConsumerWidget {
  const NearbyStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(nearbyBoardsProvider);
    final found = boards.value ?? const <NearbyBoard>[];
    final error = boards.error;
    return StageLayout(
      label: '$label · Nearby',
      title: 'Find it nearby.',
      emphasis: 'nearby',
      lead:
          'A new Orion waits for this device with a six digit code on its '
          'screen. Keep the two close.',
      reduced: reduced,
      children: [
        if (error != null) ...[
          Text(
            error is Failure ? failureCopy(error) : 'Bluetooth did not start.',
            style: context.text.body,
          ),
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OrionButton.ghost(
              label: 'Look again',
              icon: Icons.refresh,
              onPressed: () => ref.invalidate(nearbyBoardsProvider),
            ),
          ),
        ] else ...[
          MonoLabel.eyebrow(
            found.isEmpty
                ? 'Listening over Bluetooth'
                : (found.length == 1 ? '1 nearby' : '${found.length} nearby'),
            live: true,
          ),
          const SizedBox(height: Space.md),
          for (final board in found) ...[
            _NearbyCard(
              key: ValueKey(board.id),
              board: board,
              onTap: () =>
                  ref.read(bluetoothSetupProvider.notifier).pickBoard(board),
            ),
            const SizedBox(height: Space.sm),
          ],
          if (found.isEmpty)
            Text(
              'Nothing in setup mode yet. A board with no Wi-Fi opens it on '
              'its own; a board already set up opens it from Wi-Fi setup on '
              'its menu.',
              style: context.text.bodySmall,
            ),
        ],
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({super.key, required this.board, required this.onTap});

  final NearbyBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return OrionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          const OrionMark(size: 28),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        board.name,
                        style: text.title.copyWith(fontSize: 20),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    const OrionTag('setup', accent: true),
                  ],
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  board.rssi == null ? 'in range' : '${board.rssi} dBm',
                  style: text.mono,
                ),
              ],
            ),
          ),
          SignalBars(bars: BoardNetwork.barsFor(board.rssi)),
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
