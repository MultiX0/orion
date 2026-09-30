import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_info.dart';
import '../../../core/widgets/orion_select_field.dart';
import 'model_picker.dart';
import 'model_source.dart';

/// The chosen model. Tapping it opens the picker over the provider's real
/// model list.
class ModelPickerField extends ConsumerWidget {
  const ModelPickerField({
    super.key,
    required this.source,
    required this.selected,
    required this.onPick,
    this.label = '// Model',
  });

  final ModelSource source;
  final String? selected;
  final ValueChanged<String> onPick;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = ref.watch(platformInfoProvider.select((p) => p.isDesktop));
    // An empty id saved by an older build reads as no model at all.
    final chosen = (selected?.isEmpty ?? true) ? null : selected;
    return OrionSelectField(
      label: label,
      value: chosen,
      placeholder: 'Pick a model',
      mono: true,
      onTap: () async {
        final id = await showModelPicker(
          context,
          source: source,
          desktop: desktop,
          selected: chosen,
        );
        if (id != null) onPick(id);
      },
    );
  }
}
