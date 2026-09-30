import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/status_dot.dart';
import '../../features/device/data/device_providers.dart';
import '../../features/device/domain/connection_status.dart';

/// Dot plus a mono line for the socket state. Sits at the bottom of the rail.
class ConnectionBadge extends ConsumerWidget {
  const ConnectionBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    final name = ref.watch(pairedDeviceProvider.select((d) => d?.name));
    final (tone, pulse, word) = switch (status) {
      ConnectionStatus.connected => (DotTone.live, false, 'Linked'),
      ConnectionStatus.connecting => (DotTone.live, true, 'Linking'),
      ConnectionStatus.reconnecting => (DotTone.live, true, 'Relinking'),
      ConnectionStatus.disconnected => (DotTone.off, false, 'Offline'),
    };
    final dot = StatusDot(tone: tone, pulse: pulse);
    if (compact) return Center(child: dot);
    final text = context.text;
    return Row(
      children: [
        dot,
        const SizedBox(width: Space.s2 + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word.toUpperCase(),
                style: text.eyebrow.copyWith(
                  color: status == ConnectionStatus.disconnected
                      ? OrionColors.textFaint
                      : OrionColors.textCyanSoft,
                ),
              ),
              Text(
                name ?? 'No Orion paired',
                style: text.uiSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
