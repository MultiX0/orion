import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import 'model_picker_results.dart';
import 'model_source.dart';

const _dialogHeight = 560.0;

/// Opens the model picker: a dialog on desktop, a sheet on a phone.
/// Resolves to the picked model id, or null when closed.
Future<String?> showModelPicker(
  BuildContext context, {
  required ModelSource source,
  required bool desktop,
  String? selected,
}) {
  final picker = ModelPicker(source: source, selected: selected);
  final barrier = OrionColors.bgPrimary.withValues(alpha: 0.7);
  if (!desktop) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OrionColors.bgCardElevated,
      barrierColor: barrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OrionRadius.lg),
        ),
        side: BorderSide(color: OrionColors.borderSoft),
      ),
      builder: (context) => Padding(
        // The search box stays above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(heightFactor: 0.85, child: picker),
      ),
    );
  }
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: barrier,
    transitionDuration: Motion.base,
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.uiEase);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: OrionContainer.measure,
            maxHeight: _dialogHeight,
          ),
          child: Material(
            color: OrionColors.bgCardElevated,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OrionRadius.lg),
              side: const BorderSide(color: OrionColors.borderSoft),
            ),
            child: picker,
          ),
        ),
      ),
    ),
  );
}

/// A search box over the provider's models. Enter takes the first match,
/// or the typed text when nothing matches. Escape closes.
class ModelPicker extends ConsumerStatefulWidget {
  const ModelPicker({super.key, required this.source, this.selected});

  final ModelSource source;
  final String? selected;

  @override
  ConsumerState<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends ConsumerState<ModelPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(String id) => Navigator.of(context).pop(id);

  void _submit(String _) {
    final query = _search.text.trim();
    final models = ref.read(widget.source.models);
    // Still on the first fetch: wait for the list rather than guess.
    if (!models.hasValue && !models.hasError) return;
    final first = pickerRows(
      models.value ?? const [],
      query,
      widget.selected,
      fits: widget.source.fits,
    ).firstOrNull;
    if (first != null) return _pick(first.id);
    if (query.isNotEmpty) _pick(query);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MonoLabel('// Model · ${source.name}'),
            const SizedBox(height: Space.xs),
            Text('Pick a model', style: context.text.title),
            const SizedBox(height: Space.md),
            OrionTextField(
              controller: _search,
              autofocus: true,
              hint: 'Search, or type a model id',
              mono: true,
              textInputAction: TextInputAction.done,
              onSubmitted: _submit,
              trailing: const Padding(
                padding: EdgeInsets.only(right: Space.sm),
                child: Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: _search,
                builder: (context, value, _) => ModelPickerResults(
                  source: source,
                  query: value.text,
                  selected: widget.selected,
                  onPick: _pick,
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _search,
              builder: (context, value, _) => _UseTyped(
                source: source,
                query: value.text.trim(),
                onUse: _pick,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way out when the list lacks a model, hides it, or did not load.
class _UseTyped extends ConsumerWidget {
  const _UseTyped({
    required this.source,
    required this.query,
    required this.onUse,
  });

  final ModelSource source;
  final String query;
  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listed = ref.watch(
      source.models.select(
        (m) =>
            m.value?.any((model) => model.id == query && source.fits(model)) ??
            false,
      ),
    );
    if (query.isEmpty || listed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OrionButton.ghost(
          label: 'Use $query',
          icon: Icons.keyboard_return,
          size: OrionButtonSize.compact,
          onPressed: () => onUse(query),
        ),
      ),
    );
  }
}
