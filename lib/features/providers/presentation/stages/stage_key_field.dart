import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/key_field.dart';
import '../../data/llm_providers.dart';
import '../../data/providers_config_notifier.dart';
import '../../data/stage_setup.dart';
import '../../domain/llm_provider.dart';
import '../../domain/provider_kind.dart';
import '../key_on_file.dart';

/// The key for an OpenAI-compatible provider, stored under [keyId]. The
/// language model, speech to text and speech share one key per account:
/// a DeepInfra key typed here also serves the DeepInfra brain.
class StageKeyField extends ConsumerWidget {
  const StageKeyField({
    super.key,
    required this.keyId,
    required this.service,
    required this.baseUrl,
  });

  final String keyId;
  final String service;
  final String baseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onFile = ref.watch(providerKeyOnFileProvider(keyId)).value ?? false;
    return KeyField(
      id: keyId,
      label: '// $service key',
      service: service,
      onFile: onFile,
      // GET /models with the key; the same 401 rule as the brain's check.
      check: (key) {
        final known = ref
            .read(providersConfigProvider)
            .providers
            .where((p) => p.id == keyId)
            .firstOrNull;
        final probe =
            (known ??
                    LlmProvider(
                      id: keyId,
                      kind: ProviderKind.custom,
                      name: service,
                      baseUrl: baseUrl,
                    ))
                .copyWith(baseUrl: baseUrl, apiKey: key);
        return ref.read(providerRepositoryProvider).validateKey(probe);
      },
      onChecked: (key) async {
        await ref.read(stageSetupProvider.notifier).storeKey(keyId, key);
        ref.invalidate(providerKeyOnFileProvider(keyId));
      },
    );
  }
}
