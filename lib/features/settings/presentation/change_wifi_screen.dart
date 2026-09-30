import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/motion/step_switcher.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device.dart';
import '../../device/domain/device_mode.dart';
import '../../onboarding/data/bluetooth_providers.dart';
import '../../onboarding/presentation/bluetooth/bluetooth_setup_flow.dart';
import 'change_wifi.dart';
import 'lan_wifi_form.dart';

/// Change Wi-Fi for the paired board. Online, over the LAN. Out of reach,
/// it explains setup mode and runs the same Bluetooth path as onboarding,
/// which keeps the token the app already has.
class ChangeWifiScreen extends ConsumerWidget {
  const ChangeWifiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(
      deviceModeProvider.select((m) => m != DeviceMode.offline),
    );
    final viaBluetooth = ref.watch(
      changeWifiProvider.select((s) => s.bluetooth),
    );
    final canBluetooth = ref.watch(
      provisioningRepositoryProvider.select((r) => r.isSupported),
    );
    final reduced = isMotionReduced(context, ref);
    final Widget body;
    if (viaBluetooth) {
      body = BluetoothSetupFlow(
        key: const ValueKey('bluetooth'),
        label: '// Wi-Fi',
        reduced: reduced,
        onDone: (device) => _rejoined(context, ref, device),
      );
    } else if (online) {
      body = LanWifiForm(key: const ValueKey('lan'), bluetooth: canBluetooth);
    } else {
      body = SetupModeNote(
        key: const ValueKey('offline'),
        bluetooth: canBluetooth,
      );
    }
    return SafeArea(
      child: Column(
        children: [
          const OrionAppBar(
            label: '// Settings',
            title: 'Change Wi-Fi',
            emphasis: 'Wi-Fi',
            showBack: true,
          ),
          Expanded(
            child: StepSwitcher(reduced: reduced, child: body),
          ),
        ],
      ),
    );
  }

  /// The board may be at a new address now; the client follows the paired
  /// device, so recording it is the whole reconnect.
  Future<void> _rejoined(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    await ref.read(appSettingsProvider.notifier).setPairedDevice(device);
    if (context.mounted) context.go('/settings');
  }
}
