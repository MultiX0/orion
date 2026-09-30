import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/key_field.dart';
import '../../data/board_config_providers.dart';
import '../../data/providers_config_notifier.dart';
import '../../data/stage_setup.dart';
import '../../domain/voice_presets.dart';
import '../key_on_file.dart';
import 'fish_credit_note.dart';
import 'get_fish_key_button.dart';

/// The one Fish Audio key. When both voice stages are on Fish it serves
/// both, and both blocks carry it to the board.
class FishKeyBlock extends ConsumerWidget {
  const FishKeyBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = ref.watch(voiceStagesProvider);
    final onFile = ref.watch(fishKeyOnFileProvider).value ?? false;
    final serves = stages.sharedFishKey
        ? 'Serves both speaking and listening.'
        : (stages.ttsOnFish ? 'Serves speaking.' : 'Serves listening.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyField(
          id: VoicePresets.fishKeyId,
          label: '// Fish Audio key',
          service: 'Fish Audio',
          onFile: onFile,
          check: ref.read(providersConfigProvider.notifier).checkFishKey,
          onChecked: (key) async {
            await ref
                .read(stageSetupProvider.notifier)
                .storeKey(VoicePresets.fishKeyId, key);
            ref
              ..invalidate(fishKeyOnFileProvider)
              ..invalidate(fishCreditProvider);
          },
        ),
        const SizedBox(height: Space.xs),
        Text(serves, style: context.text.uiSmall),
        const SizedBox(height: Space.sm),
        const GetFishKeyButton(),
        if (stages.sttOnFish) ...[
          const SizedBox(height: Space.md),
          const FishCreditNote(),
        ],
      ],
    );
  }
}
