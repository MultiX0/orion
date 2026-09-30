import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../device/domain/device.dart';
import 'bluetooth_setup.dart';
import 'stage_layout.dart';

/// Joined and found. Continue hands the board to the rest of the app.
class DoneStage extends ConsumerWidget {
  const DoneStage({
    super.key,
    required this.label,
    required this.onDone,
    this.reduced = false,
  });

  final String label;
  final ValueChanged<Device> onDone;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(bluetoothSetupProvider.select((s) => s.device));
    final found = ref.watch(bluetoothSetupProvider.select((s) => s.foundOnLan));
    final ssid = ref.watch(bluetoothSetupProvider.select((s) => s.ssid));
    final host = device?.host ?? '';
    return StageLayout(
      label: '$label · Home',
      title: 'Orion is home.',
      emphasis: 'home',
      lead: found
          ? 'It answered on your network at $host.'
          : 'It joined ${ssid ?? 'the network'} at $host. This device cannot '
                'reach it from here yet; it will once both share a network.',
      reduced: reduced,
      children: [
        const SizedBox(height: Space.sm),
        OrionButton(
          label: 'Continue',
          trailingArrow: true,
          expand: true,
          onPressed: device == null ? null : () => onDone(device),
        ),
      ],
    );
  }
}
