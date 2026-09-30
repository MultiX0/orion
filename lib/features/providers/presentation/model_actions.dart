import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../conversation/presentation/tool_call_tag.dart';
import '../data/llm_providers.dart';
import 'provider_detail_ui.dart';

/// Test and "Use on Orion" for the picked model, with their results:
/// the reply and its timing, then the board's masked config.
class ModelActions extends ConsumerWidget {
  const ModelActions({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(providerDetailUiProvider(providerId));
    final notifier = ref.read(providerDetailUiProvider(providerId).notifier);
    final text = context.text;
    final model = ui.selectedModel;
    // Only a known "no vision" flag warns; unknown stays quiet.
    final blind = ref.watch(
      modelListProvider(providerId).select((list) {
        final picked = list.value?.where((m) => m.id == model).firstOrNull;
        return picked != null && picked.supportsVision == false;
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A Wrap, so a phone puts the two buttons on their own line.
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            OrionButton.ghost(
              label: 'Test',
              isLoading: ui.isTesting,
              onPressed: model == null ? null : notifier.test,
            ),
            OrionButton(
              label: 'Use on Orion',
              isLoading: ui.isPushing,
              onPressed: model == null ? null : notifier.useOnDevice,
            ),
          ],
        ),
        if (blind) ...[
          const SizedBox(height: Space.sm),
          Text(
            'This model cannot see. The camera\'s "ask about this" needs one '
            'with the vision badge.',
            style: text.uiSmall,
          ),
        ],
        if (ui.error != null) ...[
          const SizedBox(height: Space.sm),
          Text(ui.error!, style: text.uiSmall),
        ],
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.uiEase,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ui.testReply != null) ...[
                const SizedBox(height: Space.md),
                _Result(
                  label: 'Reply · ${formatMs(ui.testMs)}',
                  body: ui.testReply!,
                  quote: true,
                ),
              ],
              if (ui.pushed != null) ...[
                const SizedBox(height: Space.md),
                _Result(
                  label: 'Orion confirms',
                  body:
                      'model ${ui.pushed!.llm?.model ?? '?'}\n'
                      'base_url ${ui.pushed!.llm?.baseUrl ?? '?'}\n'
                      'api_key ${ui.pushed!.llm?.apiKey ?? 'none'}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.label, required this.body, this.quote = false});

  final String label;
  final String body;
  final bool quote;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return OrionCard(
      hoverable: false,
      selected: quote,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoLabel.eyebrow(label, live: false),
          const SizedBox(height: Space.xs),
          Text(
            body,
            style: quote
                ? text.title.copyWith(
                    fontSize: 20,
                    fontWeight: OrionFontWeight.regular,
                  )
                : text.mono,
          ),
        ],
      ),
    );
  }
}
