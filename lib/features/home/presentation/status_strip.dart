import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';

/// Wi-Fi, volume and wake word in one mono line. Tap to open settings.
class StatusStrip extends ConsumerWidget {
  const StatusStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rssi = ref.watch(deviceStateProvider.select((s) => s.wifiRssi));
    final volume = ref.watch(deviceStateProvider.select((s) => s.volume));
    final muted = ref.watch(deviceStateProvider.select((s) => s.muted));
    final wake = ref.watch(
      deviceStateProvider.select((s) => s.wakeWordEnabled),
    );
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go('/settings'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stale numbers from before the link dropped would lie.
                _Item(
                  icon: offline ? Icons.wifi_off_outlined : _wifiIcon(rssi),
                  label: offline ? 'no link' : '${rssi.abs()} dBm',
                ),
                const _Dot(),
                _Item(
                  icon: muted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: muted ? 'muted' : 'vol $volume',
                ),
                const _Dot(),
                _Item(
                  icon: wake
                      ? Icons.graphic_eq_rounded
                      : Icons.hearing_disabled_outlined,
                  label: wake ? 'wake on' : 'wake off',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _wifiIcon(int rssi) {
    if (rssi == 0) return Icons.wifi_off_outlined;
    if (rssi > -60) return Icons.network_wifi_rounded;
    if (rssi > -70) return Icons.network_wifi_3_bar_rounded;
    if (rssi > -80) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: OrionColors.textMuted),
        const SizedBox(width: Space.s1 + 2),
        Text(
          label.toUpperCase(),
          style: context.text.label.copyWith(color: OrionColors.textMuted),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Text('·', style: context.text.label),
    );
  }
}
