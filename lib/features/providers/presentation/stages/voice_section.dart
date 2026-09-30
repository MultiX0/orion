import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/mono_label.dart';
import '../../data/stage_setup.dart';
import 'brain_voice_form.dart';

/// Speaking and listening on the Providers screen, the same controls as
/// onboarding. The language model keeps its own section above. Reads the
/// board first, so Save sends only what changed.
class VoiceSection extends ConsumerStatefulWidget {
  const VoiceSection({super.key});

  @override
  ConsumerState<VoiceSection> createState() => _VoiceSectionState();
}

class _VoiceSectionState extends ConsumerState<VoiceSection> {
  @override
  void initState() {
    super.initState();
    ref.read(stageSetupProvider.notifier).loadFromBoard();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MonoLabel('// Voice'),
        const SizedBox(height: Space.xs),
        Text('Speaking and listening', style: text.title),
        const SizedBox(height: Space.xs),
        Text(
          'Each with its own provider. Fish Audio does both by default.',
          style: text.body,
        ),
        const SizedBox(height: Space.lg),
        const BrainVoiceForm(withMind: false),
        const SizedBox(height: Space.lg),
        SendBar(
          label: 'Save to Orion',
          onSend: () => ref
              .read(stageSetupProvider.notifier)
              .send(stages: const [Stage.stt, Stage.tts]),
        ),
      ],
    );
  }
}
