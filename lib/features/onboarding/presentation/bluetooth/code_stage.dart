import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/orion_text_field.dart';
import '../../data/ble/ble_contract.dart';
import 'bluetooth_setup.dart';
import 'setup_copy.dart';
import 'stage_layout.dart';

/// The six digits on the board's screen are the proof of possession for
/// the encrypted session. Connect runs the handshake with them.
class CodeStage extends ConsumerStatefulWidget {
  const CodeStage({super.key, required this.label, this.reduced = false});

  final String label;
  final bool reduced;

  @override
  ConsumerState<CodeStage> createState() => _CodeStageState();
}

class _CodeStageState extends ConsumerState<CodeStage> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _connect() =>
      ref.read(bluetoothSetupProvider.notifier).submitCode(_code.text);

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(bluetoothSetupProvider.select((s) => s.board?.name));
    final busy = ref.watch(bluetoothSetupProvider.select((s) => s.busy));
    final error = ref.watch(bluetoothSetupProvider.select((s) => s.error));
    return StageLayout(
      label: '${widget.label} · Code',
      title: 'Read me the code.',
      emphasis: 'code',
      lead:
          '${name ?? 'Orion'} shows six digits on its screen. They prove this '
          'phone is standing next to it.',
      reduced: widget.reduced,
      children: [
        OrionTextField(
          controller: _code,
          label: '// Code',
          hint: '000000',
          mono: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(BleContract.codeLength),
          ],
          onSubmitted: (_) => _connect(),
          error: error == null ? null : failureCopy(error),
        ),
        const SizedBox(height: Space.lg),
        OrionButton(
          label: 'Connect',
          trailingArrow: true,
          expand: true,
          isLoading: busy,
          onPressed: busy ? null : _connect,
        ),
      ],
    );
  }
}
