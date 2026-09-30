import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_chip.dart';
import '../data/providers_config_notifier.dart';
import '../domain/llm_provider.dart';
import 'stages/voice_section.dart';

/// Two sections: the brain (an LLM provider) and the voice (Fish Audio).
/// Presets open the detail route; the card shows what the board uses.
class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        children: [
          const OrionAppBar(
            label: '// Providers',
            title: 'The brain and the voice',
            emphasis: 'voice',
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
                  children: const [
                    _LlmSection(),
                    SizedBox(height: Space.lg),
                    VoiceSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LlmSection extends ConsumerWidget {
  const _LlmSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(providersConfigProvider);
    final selected = config.selected;
    final text = context.text;
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// LLM provider'),
          const SizedBox(height: Space.xs),
          Text('The brain', style: text.title),
          const SizedBox(height: Space.xs),
          Text(
            'Any OpenAI-compatible endpoint. Pick one, prove the key, '
            'choose a model, hand it to Orion.',
            style: text.body,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final p in config.providers)
                OrionChip(
                  label: p.name,
                  selected: p.id == config.selectedId,
                  onTap: () => context.go('/providers/${p.id}'),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (selected != null) _Summary(provider: selected),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.provider});

  final LlmProvider provider;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final model = provider.selectedModel;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: OrionColors.bgPrimary,
        border: Border.all(color: OrionColors.borderSubtle),
        borderRadius: BorderRadius.circular(OrionRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonoLabel.eyebrow(
                  'On Orion · ${provider.name}',
                  live: model != null,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  model ?? 'No model chosen yet',
                  style: text.ui,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  provider.baseUrl.isEmpty ? 'No endpoint' : provider.baseUrl,
                  style: text.mono,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          OrionButton.ghost(
            label: 'Configure',
            size: OrionButtonSize.compact,
            trailingArrow: true,
            onPressed: () => context.go('/providers/${provider.id}'),
          ),
        ],
      ),
    );
  }
}
