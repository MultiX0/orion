import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../providers/presentation/stages/brain_voice_form.dart';
import 'bluetooth_setup.dart';
import 'stage_layout.dart';

/// Brain and voice while the board is still in setup mode, so the keys go
/// over the encrypted Bluetooth session and never cross the LAN in the
/// clear. Testing waits until the board is on the network.
class ConfigStage extends ConsumerWidget {
  const ConfigStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.read(bluetoothSetupProvider.notifier);
    return StageLayout(
      label: '$label · Brain and voice',
      title: 'Choose how it thinks and speaks.',
      emphasis: 'speaks',
      lead:
          'Paired. These go to Orion over the encrypted Bluetooth link. A '
          'Fish key is all it takes; the rest is filled in.',
      reduced: reduced,
      children: [
        const BrainVoiceForm(canTest: false),
        const SizedBox(height: Space.lg),
        SendBar(
          label: 'Send and continue',
          onSend: setup.sendConfig,
          secondary: OrionButton.ghost(
            label: 'Later',
            onPressed: setup.toNetworks,
          ),
        ),
      ],
    );
  }
}
