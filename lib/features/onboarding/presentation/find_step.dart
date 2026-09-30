import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../device/domain/device.dart';
import '../data/bluetooth_providers.dart';
import '../data/onboarding_providers.dart';
import 'bluetooth/bluetooth_entry.dart';
import 'device_card.dart';
import 'manual_entry.dart';
import 'onboarding_notifier.dart';
import 'selected_device.dart';

/// Boards surface as discovery confirms them, each with the way it was
/// found. The orb above keeps searching until the user picks one, and
/// the address field never hides.
class FindStep extends ConsumerWidget {
  const FindStep({super.key, this.reduced = false});

  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final found =
        ref.watch(discoveredDevicesProvider).value ?? const <Device>[];
    final timedOut = ref.watch(onboardingProvider.select((s) => s.isTimedOut));
    final quiet = found.isEmpty && timedOut;
    final bluetooth = ref.watch(
      provisioningRepositoryProvider.select((r) => r.isSupported),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.measure),
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            Center(
              child: MonoLabel.eyebrow(
                found.isEmpty
                    ? (quiet ? 'Nothing charted yet' : 'Charting the network')
                    : (found.length == 1 ? '1 found' : '${found.length} found'),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              found.isEmpty
                  ? (quiet ? 'No board has answered.' : 'Listening for Orion.')
                  : 'Pick your Orion.',
              style: text.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.lg),
            for (final device in found) ...[
              DeviceCard(
                key: ValueKey(device.id),
                device: device,
                reduced: reduced,
                onTap: () {
                  ref.read(selectedDeviceProvider.notifier).set(device);
                  context.go('/onboarding/pair/${device.id}');
                },
              ),
              const SizedBox(height: Space.sm),
            ],
            if (bluetooth) ...[
              const SizedBox(height: Space.md),
              const MonoLabel('// Not on the network yet'),
              const SizedBox(height: Space.sm),
              const BluetoothEntry(),
            ],
            const SizedBox(height: Space.md),
            const MonoLabel('// Or by address'),
            const SizedBox(height: Space.sm),
            ManualEntry(showHint: quiet, bluetooth: bluetooth),
          ],
        ),
      ),
    );
  }
}
