import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness/presentation/approval_control.dart';
import 'form_step.dart';
import 'onboarding_notifier.dart';

/// Desktop only. Off, ask first, or act alone. The choice goes to the
/// board and is mirrored here, so the phone and the PC agree.
class HandsStep extends ConsumerWidget {
  const HandsStep({super.key, required this.ordinal, this.reduced = false});

  final String ordinal;
  final bool reduced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormStep(
      label: '// $ordinal · Hands',
      title: 'Hands on this PC?',
      emphasis: 'PC',
      lead:
          'Orion can open apps, read stats and run tasks here. '
          'Choose how much it asks.',
      reduced: reduced,
      onContinue: ref.read(onboardingProvider.notifier).next,
      child: const ApprovalControl(),
    );
  }
}
