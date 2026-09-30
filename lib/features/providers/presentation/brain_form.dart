import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/mono_label.dart';
import '../data/providers_config_notifier.dart';
import 'endpoint_fields.dart';
import 'key_on_file.dart';
import 'model_actions.dart';
import 'model_picker_field.dart';
import 'model_source.dart';
import 'provider_detail_ui.dart';

/// The whole brain form for one provider: endpoint and key, then the
/// model picker, then test and push. The onboarding Brain step and the
/// Providers detail screen both render exactly this.
class BrainForm extends ConsumerWidget {
  const BrainForm({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(
      providersConfigProvider.select(
        (c) => c.providers.where((p) => p.id == providerId).firstOrNull,
      ),
    );
    if (provider == null) return const SizedBox.shrink();
    final text = context.text;
    final picked = ref.watch(
      providerDetailUiProvider(providerId).select((s) => s.selectedModel),
    );
    // The list only asks the provider once there is something to ask with.
    final ready =
        !provider.needsKey ||
        (ref.watch(providerKeyOnFileProvider(providerId)).value ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MonoLabel('// Endpoint'),
        const SizedBox(height: Space.md),
        EndpointFields(key: ValueKey(providerId), provider: provider),
        const SizedBox(height: Space.lg),
        const Hairline(),
        const SizedBox(height: Space.lg),
        const MonoLabel('// Model'),
        const SizedBox(height: Space.md),
        AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.uiEase,
          child: ready
              ? Column(
                  key: const ValueKey('models'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ModelPickerField(
                      source: ModelSource.brain(provider),
                      selected: picked,
                      label: null,
                      onPick: ref
                          .read(providerDetailUiProvider(providerId).notifier)
                          .pickModel,
                    ),
                    const SizedBox(height: Space.lg),
                    ModelActions(providerId: providerId),
                  ],
                )
              : Text(
                  key: const ValueKey('waiting'),
                  'Prove a key and the models chart themselves.',
                  style: text.body,
                ),
        ),
      ],
    );
  }
}
