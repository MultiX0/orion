import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../domain/model_info.dart';
import 'key_on_file.dart';
import 'model_row.dart';
import 'model_source.dart';

/// Models that [fits] allows whose id or name holds [query], in any case.
List<ModelInfo> filterModels(
  List<ModelInfo> models,
  String query, {
  bool Function(ModelInfo model) fits = isChatModel,
}) {
  final q = query.trim().toLowerCase();
  bool hit(String? s) => s != null && s.toLowerCase().contains(q);
  return [
    for (final m in models)
      if (fits(m) && (hit(m.id) || hit(m.displayName))) m,
  ];
}

/// The rows the picker shows for [query]. With nothing typed the chosen
/// model leads, so a long list opens on it.
List<ModelInfo> pickerRows(
  List<ModelInfo> models,
  String query,
  String? selected, {
  bool Function(ModelInfo model) fits = isChatModel,
}) {
  final rows = filterModels(models, query, fits: fits);
  final at = rows.indexWhere((m) => m.id == selected);
  if (query.trim().isNotEmpty || at <= 0) return rows;
  return [rows[at], ...rows.take(at), ...rows.skip(at + 1)];
}

/// Why the list is missing, in one sentence.
String modelListProblem(
  Object error, {
  required String name,
  required bool hasKey,
}) => switch (error) {
  ProviderFailure(kind: ProviderFailureKind.badKey) =>
    hasKey
        ? '$name turned down the key on file.'
        : 'There is no $name key on this device yet.',
  ProviderFailure(statusCode: null) ||
  NetworkFailure() ||
  TimeoutFailure() => 'This device could not reach $name.',
  Failure(:final message) => message,
  _ => 'The list did not load.',
};

/// What the picker shows under the search box: the matching models, a
/// shimmer while they load, or why they did not.
class ModelPickerResults extends ConsumerWidget {
  const ModelPickerResults({
    super.key,
    required this.source,
    required this.query,
    required this.selected,
    required this.onPick,
  });

  final ModelSource source;
  final String query;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(source.models);
    final hasKey =
        !source.needsKey ||
        (ref.watch(providerKeyOnFileProvider(source.keyId)).value ?? false);
    // Riverpod retries a failed list and stays loading meanwhile, with the
    // error attached. Show the error now; a retry that lands replaces it.
    return switch (models) {
      AsyncValue(:final value?) => _Rows(
        models: pickerRows(value, query, selected, fits: source.fits),
        selected: selected,
        onPick: onPick,
      ),
      AsyncValue(:final error?) => SingleChildScrollView(
        child: EmptyState(
          label: '// No list',
          title: 'The list did not come back',
          emphasis: 'back',
          body: modelListProblem(error, name: source.name, hasKey: hasKey),
          action: OrionButton.ghost(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: () => ref.invalidate(source.models),
          ),
        ),
      ),
      _ => const Column(
        children: [
          Skeleton(height: ModelRow.height - Space.xs),
          SizedBox(height: Space.xs),
          Skeleton(height: ModelRow.height - Space.xs),
          SizedBox(height: Space.xs),
          Skeleton(height: ModelRow.height - Space.xs),
        ],
      ),
    };
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    required this.models,
    required this.selected,
    required this.onPick,
  });

  final List<ModelInfo> models;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Text('No model matches.', style: context.text.body),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: OrionColors.borderSubtle),
          borderRadius: BorderRadius.circular(OrionRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          shrinkWrap: true,
          itemExtent: ModelRow.height,
          itemCount: models.length,
          itemBuilder: (context, i) => ModelRow(
            key: ValueKey(models[i].id),
            model: models[i],
            selected: models[i].id == selected,
            onTap: () => onPick(models[i].id),
          ),
        ),
      ),
    );
  }
}
