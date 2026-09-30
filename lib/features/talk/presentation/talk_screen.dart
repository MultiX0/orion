import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import '../data/talk_notifier.dart';
import 'hold_to_talk_button.dart';
import 'live_turn_panel.dart';

/// Push to talk from the app, and a typed query for noisy rooms.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final query = _text.text.trim();
    if (query.isEmpty) return;
    await ref.read(talkProvider.notifier).send(query);
    if (mounted && ref.read(talkProvider).error == null) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final sending = ref.watch(talkProvider.select((t) => t.isSending));
    final error = ref.watch(talkProvider.select((t) => t.error));
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    return Atmosphere(
      child: SafeArea(
        child: Column(
          children: [
            const OrionAppBar(
              label: '// Talk',
              title: 'Speak, or type',
              emphasis: 'type',
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: OrionContainer.measure,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.lg,
                      Space.xxl + Space.lg,
                    ),
                    children: [
                      const Center(child: HoldToTalkButton(size: 112)),
                      const SizedBox(height: Space.xl),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: OrionTextField(
                              controller: _text,
                              label: '// Or type it',
                              hint: 'What is the weather on Titan?',
                              enabled: !offline,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          OrionButton(
                            label: 'Send',
                            trailingArrow: true,
                            isLoading: sending,
                            onPressed: offline ? null : _send,
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: Space.xs),
                        Text(
                          '$error. Try again in a moment.',
                          style: context.text.uiSmall,
                        ),
                      ],
                      const SizedBox(height: Space.xl),
                      const LiveTurnPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
