import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_dialog.dart';
import '../../../core/widgets/skeleton.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../data/device_settings_notifier.dart';
import 'app_settings_card.dart';
import 'board_card.dart';
import 'device_settings_card.dart';

/// Grouped cards: device, board, app. No dense list.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(deviceSettingsProvider);
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    ref.listen(deviceModeProvider, (prev, next) {
      if (prev == DeviceMode.offline && next != DeviceMode.offline) {
        ref.invalidate(deviceSettingsProvider);
      }
    });
    return SafeArea(
      child: Column(
        children: [
          const OrionAppBar(
            label: '// Settings',
            title: 'Orion, tuned',
            emphasis: 'tuned',
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OrionContainer.article,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.xxl + Space.lg,
                  ),
                  children: [
                    switch (settings) {
                      AsyncData(:final value) => Column(
                        children: [
                          DeviceSettingsCard(
                            key: ValueKey(value.deviceId),
                            settings: value,
                          ),
                          const SizedBox(height: Space.lg),
                          BoardCard(settings: value),
                        ],
                      ),
                      _ when offline => EmptyState(
                        label: '// Offline',
                        title: 'Orion is out of reach',
                        emphasis: 'reach',
                        body:
                            'Device settings live on the board. They return with '
                            'the link. If it moved to another network, point it '
                            'at the new one. A different board, or one that was '
                            'reset, pairs again from the start.',
                        action: Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          alignment: WrapAlignment.center,
                          children: [
                            OrionButton.ghost(
                              label: 'Change Wi-Fi',
                              icon: Icons.wifi,
                              onPressed: () => context.go('/settings/wifi'),
                            ),
                            // Unpair lives on the board card, which needs the
                            // link. Without this a stale pairing has no way out.
                            OrionButton.ghost(
                              label: 'Pair another Orion',
                              icon: Icons.link_off,
                              onPressed: () => _unpair(context, ref),
                            ),
                          ],
                        ),
                      ),
                      AsyncError(:final error) => EmptyState(
                        label: '// Error',
                        title: 'Settings did not load',
                        emphasis: 'load',
                        body: '$error'.replaceFirst(RegExp(r'^\w+: '), ''),
                        action: OrionButton.ghost(
                          label: 'Try again',
                          onPressed: () =>
                              ref.invalidate(deviceSettingsProvider),
                        ),
                      ),
                      _ => const Column(
                        children: [
                          Skeleton.card(height: 260),
                          SizedBox(height: Space.lg),
                          Skeleton.card(height: 180),
                        ],
                      ),
                    },
                    const SizedBox(height: Space.lg),
                    const AppSettingsCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unpair(BuildContext context, WidgetRef ref) async {
    final ok = await showOrionDialog(
      context,
      title: 'Pair another Orion?',
      body:
          'The app forgets this board and its token, then looks for Orion '
          'from the start.',
      confirmLabel: 'Unpair',
    );
    if (ok) await ref.read(deviceSettingsProvider.notifier).unpair();
  }
}
