import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/key_field.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../data/llm_providers.dart';
import '../data/providers_config_notifier.dart';
import '../domain/llm_provider.dart';
import '../domain/provider_kind.dart';
import 'key_on_file.dart';
import 'provider_detail_ui.dart';

/// Where a provider lives and the key that opens it. Custom endpoints get
/// an editable base URL; presets show theirs. Ollama needs no key, so it
/// gets a fetch button instead.
class EndpointFields extends ConsumerStatefulWidget {
  const EndpointFields({super.key, required this.provider});

  final LlmProvider provider;

  @override
  ConsumerState<EndpointFields> createState() => _EndpointFieldsState();
}

class _EndpointFieldsState extends ConsumerState<EndpointFields> {
  late final _baseUrl = TextEditingController(text: widget.provider.baseUrl);

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  ProviderDetailUi get _ui =>
      ref.read(providerDetailUiProvider(widget.provider.id).notifier);

  Future<void> _store(String key) async {
    await _ui.saveEndpoint(baseUrl: _baseUrl.text, apiKey: key);
    ref.invalidate(providerKeyOnFileProvider(widget.provider.id));
    ref.invalidate(modelListProvider(widget.provider.id));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final text = context.text;
    final onFile = ref.watch(providerKeyOnFileProvider(p.id)).value ?? false;
    final editable =
        p.kind == ProviderKind.custom || p.kind == ProviderKind.ollama;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable)
          OrionTextField(
            controller: _baseUrl,
            label: '// Base URL',
            hint: 'https://host/v1',
            helper: p.kind == ProviderKind.custom
                ? 'Must be OpenAI-compatible.'
                : null,
            mono: true,
            keyboardType: TextInputType.url,
          )
        else ...[
          const MonoLabel('// Base URL'),
          const SizedBox(height: Space.xs),
          Text(p.baseUrl, style: text.mono),
        ],
        const SizedBox(height: Space.md),
        if (p.needsKey)
          KeyField(
            id: p.id,
            label: '// API key',
            service: p.name,
            onFile: onFile,
            check: (key) => ref
                .read(providersConfigProvider.notifier)
                .checkProviderKey(p.id, key),
            onChecked: _store,
          )
        else
          Row(
            children: [
              OrionButton.ghost(
                label: 'Fetch models',
                icon: Icons.download_outlined,
                onPressed: () => _ui.fetchModels(baseUrl: _baseUrl.text),
              ),
            ],
          ),
      ],
    );
  }
}
