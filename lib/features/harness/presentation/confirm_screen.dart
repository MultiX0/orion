import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_button.dart';
import '../data/harness_providers.dart';
import 'confirmation_card.dart';

/// The same confirmation card as a modal over the Harness screen, for
/// when a notification brings the window to front on one call. Enter
/// approves, Escape denies, so a hand on the keyboard is enough.
class ConfirmScreen extends ConsumerWidget {
  const ConfirmScreen({super.key, required this.confirmId});

  final String confirmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(
      pendingConfirmationsProvider.select(
        (list) => list.value?.where((r) => r.id == confirmId).firstOrNull,
      ),
    );
    final repo = ref.read(harnessRepositoryProvider);
    final body = request == null
        ? EmptyState(
            label: '// Resolved',
            title: 'Already answered',
            emphasis: 'answered',
            body: 'This call was approved or denied elsewhere.',
            action: OrionButton.ghost(
              label: 'Back to the feed',
              onPressed: () => _close(context),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConfirmationCard(request: request, onDone: () => _close(context)),
              const SizedBox(height: Space.sm),
              Text(
                'ENTER APPROVES · ESC DENIES',
                style: context.text.micro,
                textAlign: TextAlign.center,
              ),
            ],
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () async {
          if (request == null) return _close(context);
          await repo.approve(request.id);
          if (context.mounted) _close(context);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () async {
          if (request == null) return _close(context);
          await repo.deny(request.id);
          if (context.mounted) _close(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: OrionContainer.form),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/harness');
    }
  }
}
