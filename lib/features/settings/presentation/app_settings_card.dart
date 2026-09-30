import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/project.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_switch.dart';
import '../../harness/presentation/approval_control.dart';
import '../../providers/presentation/stages/get_fish_key_button.dart'
    show linkOpenerProvider;
import 'setting_row.dart';

/// App-side switches, and the PC control choice on every platform. The
/// brand is dark only, so there is no theme row.
class AppSettingsCard extends ConsumerWidget {
  const AppSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = ref.watch(
      appSettingsProvider.select((s) => s.value?.reducedMotion ?? false),
    );
    final settings = ref.read(appSettingsProvider.notifier);
    final text = context.text;
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// App'),
          const SizedBox(height: Space.xs),
          Text('This app', style: text.title),
          const SizedBox(height: Space.md),
          SettingRow(
            label: 'Reduced motion',
            help: 'Entrances cut to zero. The orb slows down instead.',
            child: OrionSwitch(
              value: reduced,
              onChanged: settings.setReducedMotion,
            ),
          ),
          const SizedBox(height: Space.md),
          const Hairline(),
          const SizedBox(height: Space.md),
          const MonoLabel('// PC control'),
          const SizedBox(height: Space.xs),
          Text(
            'The same choice from the PC, the phone, or by voice. The board '
            'holds it.',
            style: text.uiSmall,
          ),
          const SizedBox(height: Space.md),
          const ApprovalControl(dense: true),
          const SizedBox(height: Space.md),
          const Hairline(),
          const SizedBox(height: Space.md),
          const MonoLabel('// About'),
          const SizedBox(height: Space.xs),
          Text(
            'Free for personal and non-commercial use, under the '
            '${OrionProject.license}. Source on GitHub, made by '
            '${OrionProject.author}.',
            style: text.uiSmall,
          ),
          const SizedBox(height: Space.sm),
          OrionButton.ghost(
            key: const ValueKey('about-github'),
            label: 'github.com/${OrionProject.author}',
            icon: Icons.open_in_new,
            onPressed: () =>
                ref.read(linkOpenerProvider)(Uri.parse(OrionProject.url)),
          ),
        ],
      ),
    );
  }
}
