import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_text_field.dart';
import '../../data/stage_setup.dart';
import '../../domain/voice_presets.dart';
import '../../domain/voice_stages.dart';
import '../model_picker_field.dart';
import '../model_source.dart';
import 'stage_key_field.dart';

/// Base URL, key, model and (for speaking) a voice, for an
/// OpenAI-compatible provider. The model is picked from the endpoint's own
/// list, the preset's model first. Key the widget by preset so a new pick
/// starts from its own defaults.
class CompatibleFields extends StatefulWidget {
  const CompatibleFields({
    super.key,
    required this.preset,
    required this.choice,
    required this.stage,
    required this.onChanged,
  });

  final StagePreset preset;
  final StageChoice choice;

  /// Stage.stt or Stage.tts. Speaking adds the voice field.
  final String stage;
  final ValueChanged<StageChoice> onChanged;

  @override
  State<CompatibleFields> createState() => _CompatibleFieldsState();
}

class _CompatibleFieldsState extends State<CompatibleFields> {
  late final _baseUrl = TextEditingController(
    text: widget.choice.baseUrl ?? widget.preset.baseUrl ?? '',
  );
  late final _voice = TextEditingController(
    text: widget.choice.voice ?? widget.preset.voice ?? '',
  );

  bool get _speaks => widget.stage == Stage.tts;
  String? get _model => widget.choice.model ?? widget.preset.model;

  @override
  void dispose() {
    _baseUrl.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _save({String? model}) => widget.onChanged(
    widget.choice.copyWith(
      baseUrl: _baseUrl.text.trim(),
      model: model ?? _model,
      voice: _speaks ? _voice.text.trim() : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrionTextField(
          controller: _baseUrl,
          label: '// Base URL',
          hint: 'https://host/v1',
          helper: p.isCustom ? 'Must be OpenAI-compatible.' : null,
          mono: true,
          keyboardType: TextInputType.url,
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: Space.md),
        StageKeyField(
          keyId: p.keyId,
          service: p.isCustom ? 'Provider' : p.name,
          baseUrl: _baseUrl.text.trim(),
        ),
        const SizedBox(height: Space.md),
        ModelPickerField(
          source: ModelSource.speech(
            preset: p,
            baseUrl: _baseUrl.text,
            stage: widget.stage,
          ),
          selected: _model,
          onPick: (id) => _save(model: id),
        ),
        if (_speaks) ...[
          const SizedBox(height: Space.md),
          OrionTextField(
            controller: _voice,
            label: '// Voice',
            hint: p.voice ?? 'voice name',
            mono: true,
            onChanged: (_) => _save(),
          ),
        ],
      ],
    );
  }
}
