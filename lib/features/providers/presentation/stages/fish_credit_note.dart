import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/mono_label.dart';
import '../../data/board_config_providers.dart';
import '../../domain/voice_presets.dart';

/// Hours of listening a dollar amount buys on Fish speech to text.
double listeningHours(double dollars) =>
    dollars / VoicePresets.fishSttDollarsPerHour;

/// Shown while speech to text is on Fish: speaking is free, listening is
/// not, and what the account's credit buys.
class FishCreditNote extends ConsumerWidget {
  const FishCreditNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    final credit = ref.watch(fishCreditProvider).value;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: OrionColors.accent.withValues(alpha: OrionAlpha.ambient),
        border: Border.all(color: OrionColors.borderCyan),
        borderRadius: BorderRadius.circular(OrionRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// About Fish credit', live: false),
          const SizedBox(height: Space.xs),
          Text(
            'Speaking is free on s2.1-pro-free. Listening is not: speech to '
            'text uses Fish API credit, separate from the free tier, at '
            r'$0.36 per hour of audio. $1 is about 2.8 hours of listening, '
            'or about 2,500 questions of 4 seconds.',
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.xs),
          Text(
            r'The key needs an account with at least $1 of API credit.',
            style: text.bodySmall.copyWith(color: OrionColors.textWhite),
          ),
          if (credit != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              _balance(credit),
              key: const ValueKey('fish-credit-balance'),
              style: text.mono.copyWith(color: OrionColors.textCyan),
            ),
          ],
        ],
      ),
    );
  }

  static String _balance(double credit) {
    if (credit <= 0) {
      return r'This account has no API credit yet. Add at least $1 at '
          'fish.audio for listening to work.';
    }
    final hours = listeningHours(credit);
    return 'This account has \$${credit.toStringAsFixed(2)} of API credit, '
        'about ${hours.toStringAsFixed(1)} hours of listening.';
  }
}
