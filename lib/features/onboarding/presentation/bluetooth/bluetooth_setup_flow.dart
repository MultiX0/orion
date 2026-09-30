import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/step_switcher.dart';
import '../../../device/domain/device.dart';
import '../../../device/domain/device_mode.dart';
import '../../domain/join_status.dart';
import 'bluetooth_setup.dart';
import 'code_stage.dart';
import 'config_stage.dart';
import 'done_stage.dart';
import 'joining_stage.dart';
import 'nearby_stage.dart';
import 'networks_stage.dart';
import 'password_stage.dart';

/// The Bluetooth path from nearby to done. Onboarding wraps it in the
/// journey's frame; Settings shows it under its own header.
class BluetoothSetupFlow extends ConsumerWidget {
  const BluetoothSetupFlow({
    super.key,
    required this.label,
    required this.onDone,
    this.reduced = false,
  });

  /// The mono label every station starts with, "// 03 · Pair" and so on.
  final String label;
  final ValueChanged<Device> onDone;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(bluetoothSetupProvider.select((s) => s.stage));
    return StepSwitcher(
      reduced: reduced,
      child: KeyedSubtree(
        key: ValueKey(stage),
        child: switch (stage) {
          SetupStage.nearby => NearbyStage(label: label, reduced: reduced),
          SetupStage.code => CodeStage(label: label, reduced: reduced),
          SetupStage.config => ConfigStage(label: label, reduced: reduced),
          SetupStage.networks => NetworksStage(label: label, reduced: reduced),
          SetupStage.password => PasswordStage(label: label, reduced: reduced),
          SetupStage.joining => JoiningStage(label: label, reduced: reduced),
          SetupStage.done => DoneStage(
            label: label,
            onDone: onDone,
            reduced: reduced,
          ),
        },
      ),
    );
  }
}

/// What the orb does on each station: it searches while the radio or the
/// board is working, errs on a failed join and wakes when Orion is home.
DeviceMode setupOrbMode(BluetoothSetupState s) => switch (s.stage) {
  SetupStage.nearby => DeviceMode.thinking,
  SetupStage.code => s.busy ? DeviceMode.thinking : DeviceMode.listening,
  SetupStage.config => DeviceMode.idle,
  SetupStage.networks => s.busy ? DeviceMode.thinking : DeviceMode.idle,
  SetupStage.password => DeviceMode.idle,
  SetupStage.joining =>
    s.join is JoinFailed || s.error != null
        ? DeviceMode.error
        : DeviceMode.thinking,
  SetupStage.done => DeviceMode.speaking,
};
