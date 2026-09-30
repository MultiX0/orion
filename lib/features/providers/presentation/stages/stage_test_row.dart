import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';
import '../../../../core/widgets/status_dot.dart';
import '../../data/board_config_providers.dart';
import '../../domain/board_config_repository.dart';

/// What a test result means, in words a person can act on. [fish] is true
/// when the stage runs on Fish, where a 402 means no API credit.
String testCopy(StageTestResult result, {required bool fish}) {
  if (result.ok) {
    return result.ms == null
        ? 'It answered. Orion is ready.'
        : 'It answered in ${result.ms} ms. Orion is ready.';
  }
  final error = result.error ?? '';
  return switch (error) {
    'busy' => 'Orion is talking, trying again.',
    'http_401' ||
    'http_403' => 'The key was turned down. Check it, or paste a fresh one.',
    'http_402' when fish =>
      r'This Fish account has no API credit. Top up at least $1 at '
          'fish.audio, then test again.',
    'http_402' => 'The provider wants payment on this account.',
    'http_404' => 'The provider does not know that model or address.',
    'timeout' => 'The provider did not answer in time. Try again in a moment.',
    'unreachable' =>
      'Orion could not reach the provider. Check the base URL, and that '
          'Orion is online.',
    _ => result.message ?? 'The provider said no ($error).',
  };
}

String testFailureCopy(Object error) => switch (error) {
  AuthFailure() => 'Orion turned down this device. Pair again from Settings.',
  NetworkFailure() || TimeoutFailure() =>
    'Orion is out of reach, so it cannot test. Test once it is on your '
        'network.',
  NotFoundFailure() => 'This board cannot test yet. Update its firmware.',
  Failure(:final message) => message,
  _ => 'The test did not run.',
};

/// Test for one stage: send what changed, ask the board to try it, say how
/// it went. Takes about a second on a real board.
class StageTestRow extends ConsumerWidget {
  const StageTestRow({super.key, required this.stage, required this.fish});

  final String stage;
  final bool fish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final test = ref.watch(stageTestProvider(stage));
    final result = test.value;
    final busy = result?.error == 'busy';
    final running = test.isLoading || busy;
    final line = switch (test) {
      AsyncError(:final error) => testFailureCopy(error),
      _ when result != null => testCopy(result, fish: fish),
      _ when test.isLoading => 'Testing with what Orion has stored.',
      _ => null,
    };
    final good = result?.ok ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        OrionButton.ghost(
          label: 'Test',
          icon: Icons.bolt_outlined,
          size: OrionButtonSize.compact,
          isLoading: running,
          onPressed: running
              ? null
              : ref.read(stageTestProvider(stage).notifier).run,
        ),
        const SizedBox(width: Space.sm),
        if (line != null) ...[
          StatusDot(
            tone: good
                ? DotTone.live
                : (running ? DotTone.idle : DotTone.white),
            pulse: running,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              line,
              key: ValueKey('test-$stage'),
              style: context.text.uiSmall.copyWith(
                color: good ? OrionColors.textCyan : OrionColors.textWhite,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
