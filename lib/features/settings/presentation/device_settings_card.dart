import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_info.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/time/posix_tz.dart';
import '../../../core/widgets/orion_card.dart';
import '../../../core/widgets/orion_switch.dart';
import '../../../core/widgets/orion_select_field.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../../device/data/device_state_notifier.dart';
import '../data/device_settings_notifier.dart';
import '../data/time_zone_sync.dart';
import '../domain/device_settings.dart';
import 'setting_row.dart';
import 'time_zone_picker.dart';

/// Name, volume, wake word, mute, language, time zone. Edits show at once; the
/// notifier rolls them back if the board says no.
class DeviceSettingsCard extends ConsumerStatefulWidget {
  const DeviceSettingsCard({super.key, required this.settings});

  final DeviceSettings settings;

  @override
  ConsumerState<DeviceSettingsCard> createState() => _DeviceSettingsCardState();
}

class _DeviceSettingsCardState extends ConsumerState<DeviceSettingsCard> {
  late final _name = TextEditingController(text: widget.settings.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final notifier = ref.read(deviceSettingsProvider.notifier);
    final muted = ref.watch(deviceStateProvider.select((s) => s.muted));
    final text = context.text;
    return OrionCard(
      hoverable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('// Device'),
          const SizedBox(height: Space.xs),
          Text('How it behaves', style: text.title),
          const SizedBox(height: Space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: OrionTextField(
                  controller: _name,
                  label: '// Name',
                  hint: 'Orion',
                  onSubmitted: notifier.setName,
                ),
              ),
              const SizedBox(width: Space.sm),
              OrionButton.ghost(
                label: 'Rename',
                onPressed: () => notifier.setName(_name.text.trim()),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          SettingRow(
            label: 'Volume',
            help: '${s.volume}',
            child: SizedBox(
              width: 180,
              child: OrionSlider(
                value: s.volume.toDouble(),
                onChangeEnd: (v) => notifier.setVolume(v.round()),
                onChanged: (_) {},
              ),
            ),
          ),
          SettingRow(
            label: 'Wake word',
            help: s.wakeWordEnabled
                ? 'Say the name to start a turn.'
                : 'Off. Touch the screen to start a turn.',
            child: OrionSwitch(
              value: s.wakeWordEnabled,
              onChanged: notifier.setWakeWord,
            ),
          ),
          // Mute lives in the board state and the config has no field for
          // it yet, so this mirrors the board and cannot flip it.
          SettingRow(
            label: 'Mute',
            help: muted
                ? 'Speaker off on the board. Orion still listens.'
                : 'Set on the board itself for now.',
            child: OrionSwitch(value: muted, label: 'Mute'),
          ),
          // The board answers in the language it hears, so there is nothing
          // to pick and no language chips.
          SettingRow(
            label: 'Language',
            help: 'Arabic or English, whichever you speak to it.',
            child: Text('Automatic', style: text.uiSmall),
          ),
          // Older firmware has no time zone field, so the row stays away.
          if (s.timeZone != null) _TimeZoneRow(timeZone: s.timeZone!),
        ],
      ),
    );
  }
}

/// The board's clock. Automatic follows this device, and the sync sends it
/// again when summer time moves the offset. A fixed offset stays put.
class _TimeZoneRow extends ConsumerWidget {
  const _TimeZoneRow({required this.timeZone});

  final String timeZone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(
      appSettingsProvider.select((s) => s.value?.timeZoneAuto ?? true),
    );
    final desktop = ref.watch(platformInfoProvider.select((p) => p.isDesktop));
    final offset = PosixTz.offsetOf(timeZone);
    final zone = offset == null ? timeZone : PosixTz.label(offset);
    return SettingRow(
      label: 'Time zone',
      help: 'The clock on the board and the time Orion is told.',
      child: SizedBox(
        width: 200,
        child: OrionSelectField(
          value: auto ? 'Automatic, $zone' : zone,
          mono: true,
          onTap: () async {
            final choice = await showTimeZonePicker(
              context,
              desktop: desktop,
              auto: auto,
              current: offset,
            );
            if (choice == null) return;
            await ref
                .read(appSettingsProvider.notifier)
                .setTimeZoneAuto(choice.auto);
            final tz = choice.auto
                ? TimeZoneSync.here()
                : PosixTz.fromOffset(choice.offset);
            await ref.read(deviceSettingsProvider.notifier).setTimeZone(tz);
          },
        ),
      ),
    );
  }
}
