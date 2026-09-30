import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../data/providers_config_notifier.dart';
import '../../data/stage_setup.dart';
import '../../domain/voice_presets.dart';
import '../../domain/voice_stages.dart';
import '../voice_card.dart';
import '../voice_ui.dart';
import 'compatible_fields.dart';
import 'stage_card.dart';
import 'stage_test_row.dart';

/// Text to speech: Fish with Orion Voice by default, or any
/// OpenAI-compatible speech endpoint.
class SpeakCard extends ConsumerWidget {
  const SpeakCard({super.key, this.canTest = true});

  final bool canTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(voiceStagesProvider.select((s) => s.tts));
    final preset = VoicePresets.ttsById(choice.presetId);
    final setup = ref.read(stageSetupProvider.notifier);
    return StageCard(
      label: '// Speaking · text to speech',
      title: 'How it sounds',
      lead: 'The voice Orion answers in.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StagePresetChips(
            presets: VoicePresets.tts,
            selectedId: preset.id,
            onPick: (p) => setup.setTts(StageChoice(presetId: p.id)),
          ),
          const SizedBox(height: Space.md),
          if (preset.isFish)
            const _FishVoice()
          else
            CompatibleFields(
              key: ValueKey('tts-${preset.id}'),
              preset: preset,
              choice: choice,
              stage: Stage.tts,
              onChanged: setup.setTts,
            ),
          if (canTest) ...[
            const SizedBox(height: Space.md),
            StageTestRow(stage: Stage.tts, fish: preset.isFish),
          ],
        ],
      ),
    );
  }
}

/// Fish: the model chips and Orion Voice, the product's own voice, with a
/// real preview. It is the only Fish voice the app offers.
class _FishVoice extends ConsumerWidget {
  const _FishVoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fish = ref.watch(providersConfigProvider.select((c) => c.fish));
    final playing = ref.watch(
      voiceUiProvider.select((s) => s.playingId == previewClipId),
    );
    final loading = ref.watch(voiceUiProvider.select((s) => s.isPreviewing));
    final config = ref.read(providersConfigProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModelChips(
          models: VoicePresets.fishTts.models,
          selected: fish.ttsModel,
          onPick: (m) => config.setFish(fish.copyWith(ttsModel: m)),
        ),
        const SizedBox(height: Space.md),
        VoiceCard(
          voiceId: VoicePresets.orionVoiceId,
          title: VoicePresets.orionVoiceName,
          ttsModel: fish.ttsModel,
          isPlaying: playing,
          isLoading: loading,
          onPreview: ref.read(voiceUiProvider.notifier).preview,
        ),
      ],
    );
  }
}
