import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/emphasis_text.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import 'step_header.dart';

/// The end of the line. The orb above is the live one now, so it wakes
/// the moment the socket lands. One line, one button.
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key, required this.ordinal, this.reduced = false});

  final String ordinal;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final awake = ref.watch(deviceModeProvider) != DeviceMode.offline;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.measure),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MonoLabel.eyebrow(
                awake ? 'Orion is awake' : 'Waking up',
              ).animate(effects: rise(0, reduced)),
              const SizedBox(height: Space.md),
              EmphasisText(
                'The constellation is charted.',
                emphasis: 'charted',
                style: text.display,
                textAlign: TextAlign.center,
              ).animate(effects: rise(1, reduced)),
              const SizedBox(height: Space.md),
              Text(
                'Everything you skipped waits under Providers and Settings. '
                'Orion does not.',
                style: text.lead,
                textAlign: TextAlign.center,
              ).animate(effects: rise(2, reduced)),
              const SizedBox(height: Space.xl),
              OrionButton(
                label: 'Go to Orion',
                trailingArrow: true,
                onPressed: () => context.go('/'),
              ).animate(effects: rise(3, reduced)),
              const SizedBox(height: Space.md),
              MonoLabel.micro(
                '// $ordinal · Ready',
                textAlign: TextAlign.center,
              ).animate(effects: rise(4, reduced)),
            ],
          ),
        ),
      ),
    );
  }
}
