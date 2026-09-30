import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/motion.dart';
import '../result.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'key_check.dart';
import 'mono_label.dart';
import 'orion_button.dart';
import 'orion_text_field.dart';

/// The one field for every API key in the app. Masked with a reveal
/// toggle, a Check that proves the key, and a hairline that turns accent
/// once it does. The key goes to onChecked and nowhere else: not a URL,
/// not a log line, not a toast.
class KeyField extends ConsumerStatefulWidget {
  const KeyField({
    super.key,
    required this.id,
    required this.check,
    required this.onChecked,
    this.label = '// API key',
    this.service = 'The provider',
    this.onFile = false,
  });

  /// Names the check state, one per key: a provider id, or "fish".
  final String id;
  final Future<Result<void>> Function(String key) check;

  /// Store the key. Called only after a check passed, or when the check
  /// is not available yet and the key is kept as typed.
  final Future<void> Function(String key) onChecked;
  final String label;

  /// Who rejects the key in the error line.
  final String service;

  /// A key is already in the keychain, so an empty field is fine.
  final bool onFile;

  @override
  ConsumerState<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends ConsumerState<KeyField> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _check() => ref
      .read(keyCheckProvider(widget.id).notifier)
      .run(_key.text.trim(), check: widget.check, store: widget.onChecked);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(keyCheckProvider(widget.id));
    final notifier = ref.read(keyCheckProvider(widget.id).notifier);
    final text = context.text;
    final ok = state.status == KeyStatus.ok;
    final (line, live) = switch (state.status) {
      KeyStatus.ok => ('Accepted. Kept in the keychain.', true),
      KeyStatus.saved => (
        'Kept in the keychain. The check itself is next.',
        false,
      ),
      KeyStatus.bad => (
        state.message == 'Paste a key first.'
            ? state.message!
            : '${widget.service} did not accept this key.',
        false,
      ),
      KeyStatus.checking => ('Asking ${widget.service}.', true),
      KeyStatus.idle => (
        widget.onFile ? 'A key is on file. Enter one to replace it.' : null,
        false,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonoLabel(widget.label),
        const SizedBox(height: Space.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OrionTextField(
                controller: _key,
                hint: widget.onFile ? 'Saved. Enter to replace.' : 'sk-...',
                obscure: true,
                mono: true,
                accent: ok,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (state.status != KeyStatus.idle) notifier.reset();
                },
                onSubmitted: (_) => _check(),
              ),
            ),
            const SizedBox(width: Space.sm),
            OrionButton.ghost(
              label: 'Check',
              isLoading: state.status == KeyStatus.checking,
              onPressed: state.status == KeyStatus.checking ? null : _check,
            ),
          ],
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.uiEase,
          alignment: Alignment.topLeft,
          child: line == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: ok || live
                      ? MonoLabel.eyebrow(line, live: live)
                      : Text(
                          line,
                          style: text.uiSmall.copyWith(
                            color: state.status == KeyStatus.bad
                                ? OrionColors.textWhite
                                : OrionColors.textMuted,
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}
