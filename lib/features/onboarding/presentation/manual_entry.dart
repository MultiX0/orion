import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../data/onboarding_providers.dart';
import 'selected_device.dart';

/// Type an address, confirm a board answers, then go pair it like a
/// discovered one. Always reachable from discover.
class ManualEntry extends ConsumerStatefulWidget {
  const ManualEntry({
    super.key,
    required this.showHint,
    this.bluetooth = false,
  });

  /// True after discovery ran dry, when first-setup instructions help.
  final bool showHint;

  /// True when a new board can be set up over Bluetooth instead.
  final bool bluetooth;

  @override
  ConsumerState<ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends ConsumerState<ManualEntry> {
  final _host = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final device = await ref
        .read(pairingProvider.notifier)
        .probeAddress(_host.text.trim());
    if (device == null || !mounted) return;
    ref.read(selectedDeviceProvider.notifier).set(device);
    context.go('/onboarding/pair/${device.id}');
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingProvider);
    final error = pairing.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHint) ...[
          Text(
            widget.bluetooth
                ? 'Nothing answered on the network. A new Orion sets up over '
                      'Bluetooth, above. A board without it opens its own '
                      'network, Orion-xxxx: join it and enter 192.168.4.1.'
                : 'Nothing answered. On first setup Orion opens its own '
                      'network, named Orion-xxxx. Join it, then enter '
                      '192.168.4.1 here.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.md),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: OrionTextField(
                controller: _host,
                label: '// Address',
                hint: '192.168.1.40 or orion.local',
                mono: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _probe(),
                error: error == null ? null : _copyFor(error),
              ),
            ),
            const SizedBox(width: Space.sm),
            OrionButton(
              label: 'Pair',
              isLoading: pairing.isLoading,
              onPressed: pairing.isLoading ? null : _probe,
            ),
          ],
        ),
      ],
    );
  }

  String _copyFor(Object error) => '$error'.replaceFirst(RegExp(r'^\w+: '), '');
}
