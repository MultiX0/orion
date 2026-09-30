import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/posix_tz.dart';
import '../../../core/widgets/mono_label.dart';

/// What the picker hands back: follow this device, or one fixed offset.
typedef TimeZoneChoice = ({bool auto, Duration offset});

const _dialogHeight = 560.0;

/// Opens the time zone list: a dialog on desktop, a sheet on a phone.
/// Resolves to the choice, or null when closed.
Future<TimeZoneChoice?> showTimeZonePicker(
  BuildContext context, {
  required bool desktop,
  required bool auto,
  Duration? current,
}) {
  final picker = _TimeZoneList(auto: auto, current: current);
  final barrier = OrionColors.bgPrimary.withValues(alpha: 0.7);
  if (!desktop) {
    return showModalBottomSheet<TimeZoneChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OrionColors.bgCardElevated,
      barrierColor: barrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OrionRadius.lg),
        ),
        side: BorderSide(color: OrionColors.borderSoft),
      ),
      builder: (context) =>
          FractionallySizedBox(heightFactor: 0.75, child: picker),
    );
  }
  return showGeneralDialog<TimeZoneChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: barrier,
    transitionDuration: Motion.base,
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Motion.uiEase),
      child: child,
    ),
    pageBuilder: (context, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: OrionContainer.measure,
            maxHeight: _dialogHeight,
          ),
          child: Material(
            color: OrionColors.bgCardElevated,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OrionRadius.lg),
              side: const BorderSide(color: OrionColors.borderSoft),
            ),
            child: picker,
          ),
        ),
      ),
    ),
  );
}

class _TimeZoneList extends StatelessWidget {
  const _TimeZoneList({required this.auto, this.current});

  final bool auto;
  final Duration? current;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final here = DateTime.now().timeZoneOffset;
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// Time zone'),
          const SizedBox(height: Space.xs),
          Text('Where the board is', style: text.title),
          const SizedBox(height: Space.md),
          Expanded(
            child: ListView(
              children: [
                _Row(
                  key: const ValueKey('tz-auto'),
                  title: 'Automatic',
                  detail: 'Follows this device, now ${PosixTz.label(here)}',
                  selected: auto,
                  onTap: () =>
                      Navigator.of(context).pop((auto: true, offset: here)),
                ),
                for (final minutes in PosixTz.offsetsInUse)
                  _Row(
                    key: ValueKey('tz-$minutes'),
                    title: PosixTz.label(Duration(minutes: minutes)),
                    selected: !auto && current?.inMinutes == minutes,
                    onTap: () => Navigator.of(
                      context,
                    ).pop((auto: false, offset: Duration(minutes: minutes))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One choice, in the model picker's look: the chosen one carries a cyan
/// hairline.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: selected ? OrionColors.bgHighlight : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 1,
                height: 20,
                child: ColoredBox(
                  color: selected ? OrionColors.textCyan : Colors.transparent,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.ui.copyWith(
                        color: selected
                            ? OrionColors.textWhite
                            : OrionColors.textMuted,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: text.mono.copyWith(color: OrionColors.textFaint),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
