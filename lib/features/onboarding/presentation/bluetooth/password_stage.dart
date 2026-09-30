import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/orion_text_field.dart';
import 'bluetooth_setup.dart';
import 'setup_copy.dart';
import 'stage_layout.dart';

/// The password for the chosen network, or a name and a password for a
/// hidden one. An open network needs neither, just Join.
class PasswordStage extends ConsumerStatefulWidget {
  const PasswordStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  ConsumerState<PasswordStage> createState() => _PasswordStageState();
}

class _PasswordStageState extends ConsumerState<PasswordStage> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ssid.text = ref.read(bluetoothSetupProvider).ssid ?? '';
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void _join() => ref
      .read(bluetoothSetupProvider.notifier)
      .join(ssid: _ssid.text, password: _password.text);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bluetoothSetupProvider);
    final name = s.ssid ?? 'the network';
    final error = s.error;
    return StageLayout(
      label: '${widget.label} · Password',
      title: s.hidden ? 'Name the hidden one.' : 'Hand it the key.',
      emphasis: s.hidden ? 'hidden' : 'key',
      lead: s.hidden
          ? 'A hidden network does not announce itself. Type its name exactly '
                'as the router spells it.'
          : (s.secured
                ? 'The password for $name. It travels encrypted and stays on '
                      'the board.'
                : '$name is open. No password needed.'),
      reduced: widget.reduced,
      children: [
        if (s.hidden) ...[
          OrionTextField(
            controller: _ssid,
            label: '// Network name',
            hint: 'Exactly as the router spells it',
            autofocus: true,
          ),
          const SizedBox(height: Space.md),
        ],
        if (s.secured)
          OrionTextField(
            controller: _password,
            label: '// Password',
            hint: s.hidden ? 'Leave empty for an open network' : null,
            obscure: true,
            autofocus: !s.hidden,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _join(),
          ),
        if (error != null) StageError(failureCopy(error)),
        const SizedBox(height: Space.lg),
        OrionButton(
          label: 'Join',
          trailingArrow: true,
          expand: true,
          onPressed: s.busy ? null : _join,
        ),
      ],
    );
  }
}
