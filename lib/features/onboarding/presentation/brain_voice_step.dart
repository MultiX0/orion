import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../providers/data/stage_setup.dart';
import '../../providers/presentation/stages/brain_voice_form.dart';
import 'onboarding_notifier.dart';
import 'step_header.dart';

/// Brain and voice, once the board is paired and on the network. Filled
/// with the board's defaults, so a Fish key alone is enough to go on.
class BrainVoiceStep extends ConsumerWidget {
  const BrainVoiceStep({
    super.key,
    required this.ordinal,
    this.reduced = false,
  });

  final String ordinal;
  final bool reduced;

  Future<void> _send(WidgetRef ref) async {
    final sent = await ref.read(stageSetupProvider.notifier).send();
    if (sent.isOk) ref.read(onboardingProvider.notifier).next();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.article),
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            StepHeader(
              label: '// $ordinal · Brain and voice',
              title: 'Choose how it thinks and speaks.',
              emphasis: 'speaks',
              lead:
                  'Fish Audio speaks and listens, Gemma 4 thinks on DeepInfra. '
                  'A Fish key is all it takes; change anything you like.',
              reduced: reduced,
            ),
            const SizedBox(height: Space.lg),
            const BrainVoiceForm().animate(effects: rise(3, reduced)),
            const SizedBox(height: Space.xl),
            SendBar(label: 'Send to Orion', onSend: () => _send(ref)),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}
