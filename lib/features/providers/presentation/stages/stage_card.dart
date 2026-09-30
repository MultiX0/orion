import 'package:flutter/material.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/mono_label.dart';
import '../../../../core/widgets/orion_card.dart';
import '../../../../core/widgets/orion_chip.dart';
import '../../domain/voice_presets.dart';

/// One stage of a turn: its label, a title, one line, the provider chips
/// and whatever that provider needs.
class StageCard extends StatelessWidget {
  const StageCard({
    super.key,
    required this.label,
    required this.title,
    required this.lead,
    required this.child,
  });

  final String label;
  final String title;
  final String lead;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MonoLabel(label),
          const SizedBox(height: Space.xs),
          Text(title, style: text.title),
          const SizedBox(height: Space.xs),
          Text(lead, style: text.bodySmall),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

/// One chip per preset, wrapping on a narrow phone.
class StagePresetChips extends StatelessWidget {
  const StagePresetChips({
    super.key,
    required this.presets,
    required this.selectedId,
    required this.onPick,
  });

  final List<StagePreset> presets;
  final String selectedId;
  final ValueChanged<StagePreset> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final p in presets)
          OrionChip(
            label: p.name,
            selected: p.id == selectedId,
            onTap: () => onPick(p),
          ),
      ],
    );
  }
}

/// Model chips for a Fish stage.
class ModelChips extends StatelessWidget {
  const ModelChips({
    super.key,
    required this.models,
    required this.selected,
    required this.onPick,
  });

  final List<String> models;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MonoLabel('// Model'),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final m in models)
              OrionChip(
                label: m,
                selected: m == selected,
                onTap: () => onPick(m),
              ),
          ],
        ),
      ],
    );
  }
}
