import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../../../core/widgets/orion_toast.dart';
import 'camera_ui_notifier.dart';

/// Shutter, Save, "Ask about this", and the one-line question field.
class CameraControls extends ConsumerStatefulWidget {
  const CameraControls({super.key});

  @override
  ConsumerState<CameraControls> createState() => _CameraControlsState();
}

class _CameraControlsState extends ConsumerState<CameraControls> {
  final _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    await ref.read(cameraUiProvider.notifier).ask(_question.text);
    if (mounted && ref.read(cameraUiProvider).askTurnId != null) {
      _question.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cameraUiProvider.select((s) => s.savedPath), (_, path) {
      if (path != null) {
        showOrionToast(context, label: '// Saved', message: path, mono: true);
      }
    });
    final ui = ref.watch(cameraUiProvider);
    final notifier = ref.read(cameraUiProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.sm,
          children: [
            OrionButton.ghost(
              label: ui.isAskOpen ? 'Never mind' : 'Ask about this',
              icon: Icons.auto_awesome_outlined,
              onPressed: notifier.toggleAsk,
            ),
            _Shutter(busy: ui.isCapturing, onTap: notifier.capture),
            OrionButton.ghost(
              label: 'Save',
              icon: Icons.save_alt_outlined,
              isLoading: ui.isSaving,
              onPressed: ui.snapshot == null || ui.isSaving
                  ? null
                  : notifier.save,
            ),
          ],
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.uiEase,
          alignment: Alignment.topCenter,
          child: ui.isAskOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: OrionTextField(
                          controller: _question,
                          hint: 'What is on the desk?',
                          autofocus: true,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _ask(),
                          error: ui.error,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      OrionButton(
                        label: 'Ask',
                        isLoading: ui.isAsking,
                        trailingArrow: true,
                        onPressed: _ask,
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (ui.error != null && !ui.isAskOpen) ...[
          const SizedBox(height: Space.xs),
          Text(
            ui.error!,
            style: context.text.uiSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Snapshot',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: busy ? OrionColors.borderCyan : OrionColors.borderSoft,
              ),
            ),
            child: AnimatedContainer(
              duration: Motion.fast,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busy ? OrionColors.textCyan : OrionColors.textWhite,
                boxShadow: busy ? const [OrionShadow.glowSm] : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
