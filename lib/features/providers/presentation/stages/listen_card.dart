import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../data/stage_setup.dart';
import '../../domain/voice_presets.dart';
import '../../domain/voice_stages.dart';
import 'compatible_fields.dart';
import 'stage_card.dart';
import 'stage_test_row.dart';

/// Speech to text: Fish by default, any OpenAI-compatible service instead.
class ListenCard extends ConsumerWidget {
  const ListenCard({super.key, this.canTest = true});

  final bool canTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(voiceStagesProvider.select((s) => s.stt));
    final preset = VoicePresets.sttById(choice.presetId);
    final setup = ref.read(stageSetupProvider.notifier);
    return StageCard(
      label: '// Listening · speech to text',
      title: 'How it hears',
      lead: 'What turns your voice into words on the board.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StagePresetChips(
            presets: VoicePresets.stt,
            selectedId: preset.id,
            onPick: (p) =>
                setup.setStt(StageChoice(presetId: p.id, model: p.model)),
          ),
          const SizedBox(height: Space.md),
          if (preset.isFish)
            ModelChips(
              models: preset.models,
              selected: choice.model ?? preset.model,
              onPick: (m) => setup.setStt(choice.copyWith(model: m)),
            )
          else
            CompatibleFields(
              key: ValueKey('stt-${preset.id}'),
              preset: preset,
              choice: choice,
              stage: Stage.stt,
              onChanged: setup.setStt,
            ),
          if (canTest) ...[
            const SizedBox(height: Space.md),
            StageTestRow(stage: Stage.stt, fish: preset.isFish),
          ],
        ],
      ),
    );
  }
}
