import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../data/stage_setup.dart';
import '../../domain/board_config_repository.dart';
import 'fish_key_block.dart';
import 'listen_card.dart';
import 'mind_card.dart';
import 'speak_card.dart';

/// Brain and voice: the Fish key when any stage uses Fish, then speaking,
/// listening and, when [withMind], the language model. Onboarding, the
/// Bluetooth setup and the Providers screen all render this.
class BrainVoiceForm extends ConsumerWidget {
  const BrainVoiceForm({super.key, this.withMind = true, this.canTest = true});

  final bool withMind;

  /// Testing needs the board on the network, so not during Bluetooth setup.
  final bool canTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anyFish = ref.watch(voiceStagesProvider.select((s) => s.anyFish));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (anyFish) ...[
          const FishKeyBlock(),
          const SizedBox(height: Space.lg),
        ],
        SpeakCard(canTest: canTest),
        const SizedBox(height: Space.md),
        ListenCard(canTest: canTest),
        if (withMind) ...[
          const SizedBox(height: Space.md),
          MindCard(canTest: canTest),
        ],
      ],
    );
  }
}

/// The send button and what came of it.
class SendBar extends ConsumerWidget {
  const SendBar({
    super.key,
    required this.label,
    required this.onSend,
    this.secondary,
  });

  final String label;
  final VoidCallback onSend;
  final Widget? secondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stageSetupProvider);
    final line = switch (s) {
      StageSendState(:final error?) => sendFailureCopy(error),
      StageSendState(nothingToSend: true) => 'Orion already has all of this.',
      StageSendState(:final route?) => sendRouteCopy(route),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (line != null) ...[
          Text(
            line,
            key: const ValueKey('send-line'),
            style: context.text.uiSmall.copyWith(
              color: s.error == null
                  ? OrionColors.textCyan
                  : OrionColors.textWhite,
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          alignment: WrapAlignment.end,
          children: [
            ?secondary,
            OrionButton(
              label: label,
              trailingArrow: true,
              isLoading: s.busy,
              onPressed: s.busy ? null : onSend,
            ),
          ],
        ),
      ],
    );
  }
}

String sendRouteCopy(ConfigRoute route) => switch (route) {
  ConfigRoute.bluetooth => 'Sent over the encrypted Bluetooth link.',
  ConfigRoute.lan => 'Orion has it. The next turn uses it.',
  ConfigRoute.lanVersion1 =>
    'This board runs older firmware: it took the model and the Fish voice. '
        'Other speech providers need a firmware update.',
};

String sendFailureCopy(Failure failure) => switch (failure) {
  AuthFailure() => 'Orion turned down this device. Pair again from Settings.',
  NetworkFailure() || TimeoutFailure() =>
    'Orion is out of reach. Keys stay on this device until it is back.',
  DeviceFailure(code: 'invalid_config', :final message) =>
    'Orion did not take that: $message',
  BluetoothFailure() =>
    'The Bluetooth link dropped. Bring the phone closer and send again.',
  Failure(:final message) => message,
};
