import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_chip.dart';
import '../data/providers_config_notifier.dart';

/// One chip per provider. The caller decides what a tap means: the
/// onboarding step edits in place, the Providers screen opens a route.
class PresetChips extends ConsumerWidget {
  const PresetChips({
    super.key,
    required this.selectedId,
    required this.onPick,
  });

  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(
      providersConfigProvider.select(
        (c) => [for (final p in c.providers) (p.id, p.name)],
      ),
    );
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final (id, name) in providers)
          OrionChip(
            label: name,
            selected: id == selectedId,
            onTap: () => onPick(id),
          ),
      ],
    );
  }
}
