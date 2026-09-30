import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_dialog.dart';
import '../data/device_settings_notifier.dart';
import '../domain/device_settings.dart';
import 'setting_row.dart';

/// Firmware, address, uptime, a way to move it to another network, and
/// the two buttons that need a second thought: restart and unpair.
class BoardCard extends ConsumerWidget {
  const BoardCard({super.key, required this.settings});

  final DeviceSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settings;
    final text = context.text;
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// Board'),
          const SizedBox(height: Space.xs),
          Text('What it is', style: text.title),
          const SizedBox(height: Space.lg),
          // Facts wrap instead of sharing a row, so a long address on a
          // phone never runs into its neighbour.
          Wrap(
            spacing: Space.xl,
            runSpacing: Space.md,
            children: [
              FactTile(label: 'firmware', value: s.fwVersion),
              FactTile(label: 'address', value: s.ip),
              FactTile(label: 'uptime', value: _uptime(s.uptimeS)),
              FactTile(label: 'device id', value: s.deviceId),
              FactTile(label: 'camera', value: s.hasCamera ? 'yes' : 'no'),
            ],
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OrionButton.ghost(
                label: 'Change Wi-Fi',
                icon: Icons.wifi,
                onPressed: () => context.go('/settings/wifi'),
              ),
              OrionButton.ghost(
                label: 'Restart',
                icon: Icons.restart_alt,
                onPressed: () => _restart(context, ref),
              ),
              OrionButton.secondary(
                label: 'Unpair this Orion',
                onPressed: () => _unpair(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final ok = await showOrionDialog(
      context,
      title: 'Restart Orion?',
      body:
          'It drops off the network for a few seconds and comes back on '
          'its own.',
      confirmLabel: 'Restart',
    );
    if (ok) await ref.read(deviceSettingsProvider.notifier).restart();
  }

  Future<void> _unpair(BuildContext context, WidgetRef ref) async {
    final ok = await showOrionDialog(
      context,
      title: 'Unpair this Orion?',
      body:
          'The app forgets the board and its token. You can pair again '
          'from the start.',
      confirmLabel: 'Unpair',
    );
    if (ok) await ref.read(deviceSettingsProvider.notifier).unpair();
  }

  String _uptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) {
      return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
    }
    return '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h';
  }
}
