import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/theme_context.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/orion_button.dart';

/// Where a Fish Audio key comes from. Exactly this link, referral included.
const fishKeyUrl = 'https://fish.audio?fpr=d9z5u5&fp_sid=ipdev';

/// Opens a link in the external browser. A provider so tests can watch the
/// link go out without a browser.
final linkOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The door to a Fish Audio account, next to the key field.
class GetFishKeyButton extends ConsumerWidget {
  const GetFishKeyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OrionButton.secondary(
          label: 'Get your Fish Audio API key',
          icon: Icons.open_in_new,
          onPressed: () => ref.read(linkOpenerProvider)(Uri.parse(fishKeyUrl)),
        ),
        Text('Opens fish.audio in the browser.', style: context.text.uiSmall),
      ],
    );
  }
}
