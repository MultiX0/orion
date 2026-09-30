import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../data/providers_config_notifier.dart';
import '../../data/stage_setup.dart';
import '../../domain/provider_presets.dart';
import '../model_picker_field.dart';
import '../model_source.dart';
import '../preset_chips.dart';
import 'stage_card.dart';
import 'stage_key_field.dart';
import 'stage_test_row.dart';

/// The language model, compact: provider, key, model. Gemma 4 31B on
/// DeepInfra is picked already, and an empty key keeps the one on the
/// board. The model comes from the provider's own list.
class MindCard extends ConsumerWidget {
  const MindCard({super.key, this.canTest = true});

  final bool canTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(
      providersConfigProvider.select(
        (c) => c.selected ?? ProviderPresets.deepinfra,
      ),
    );
    final config = ref.read(providersConfigProvider.notifier);
    return StageCard(
      label: '// Mind · language model',
      title: 'How it thinks',
      lead: 'Any OpenAI-compatible model. The board streams its answers.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PresetChips(selectedId: provider.id, onPick: config.select),
          const SizedBox(height: Space.md),
          if (provider.needsKey) ...[
            StageKeyField(
              key: ValueKey('llm-key-${provider.id}'),
              keyId: provider.id,
              service: provider.name,
              baseUrl: provider.baseUrl,
            ),
            const SizedBox(height: Space.md),
          ],
          ModelPickerField(
            key: ValueKey('llm-model-${provider.id}'),
            source: ModelSource.brain(provider),
            selected: provider.selectedModel,
            label: '// Model · everyday answers, fast',
            onPick: (id) => config.upsert(provider.copyWith(selectedModel: id)),
          ),
          const SizedBox(height: Space.md),
          // The PC and the phone click through apps, search and check their
          // work: a model that thinks first does that, a fast one tends to
          // claim it played a song it only searched for.
          ModelPickerField(
            key: ValueKey('llm-thinking-${provider.id}'),
            source: ModelSource.brain(provider),
            selected: provider.thinkingModel ?? provider.selectedModel,
            label: '// Thinking model · tasks on the PC and phone',
            onPick: (id) => config.upsert(provider.copyWith(thinkingModel: id)),
          ),
          if (canTest) ...[
            const SizedBox(height: Space.md),
            const StageTestRow(stage: Stage.llm, fish: false),
          ],
        ],
      ),
    );
  }
}
