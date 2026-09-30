import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/motion/step_switcher.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/orion_text_field.dart';
import '../../device/domain/device_mode.dart';
import '../data/onboarding_providers.dart';
import 'onboarding_frame.dart';
import 'onboarding_notifier.dart';
import 'selected_device.dart';
import 'step_header.dart';

/// A board found on the network pairs with the six digits it puts on its own
/// screen: no Wi-Fi to type, so a reinstalled app or a second device gets in
/// the same way. A board without code pairing gets the old form instead, Wi-Fi
/// and a name for its setup network, and the orb thinks while it reboots.
/// Success is caught by OnboardingScreen underneath, which resumes at Brain.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

enum _Mode { asking, code, wifi }

class _PairScreenState extends ConsumerState<PairScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController(text: 'Orion');
  final _code = TextEditingController();
  var _mode = _Mode.asking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForCode());
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _host => ref.read(selectedDeviceProvider)?.host ?? widget.deviceId;

  Future<void> _askForCode() async {
    setState(() => _mode = _Mode.asking);
    _code.clear();
    final shown = await ref.read(pairingProvider.notifier).requestCode(_host);
    if (!mounted) return;
    // Null is an error, shown on the code form with a way to ask again.
    setState(() => _mode = shown == false ? _Mode.wifi : _Mode.code);
  }

  void _connect() => ref
      .read(pairingProvider.notifier)
      .pairWithCode(host: _host, code: _code.text);

  void _pair(String host) => ref
      .read(pairingProvider.notifier)
      .pair(
        host: host,
        wifiSsid: _ssid.text.trim(),
        wifiPassword: _password.text,
        deviceName: _name.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(selectedDeviceProvider);
    final host = device?.host ?? widget.deviceId;
    final pairing = ref.watch(pairingProvider);
    final reduced = isMotionReduced(context, ref);
    final busy = pairing.isLoading;
    final rebooting = busy && _mode == _Mode.wifi;
    final name = device?.name ?? widget.deviceId;
    return OnboardingFrame(
      step: OnboardingStep.pair,
      hero: rebooting,
      orbMode: busy ? DeviceMode.thinking : DeviceMode.idle,
      onBack: busy ? null : () => context.go('/onboarding'),
      child: StepSwitcher(
        reduced: reduced,
        child: switch (_mode) {
          _Mode.asking => const _Asking(key: ValueKey('asking')),
          _Mode.code => _CodeForm(
            key: const ValueKey('code'),
            name: name,
            code: _code,
            error: pairing.error,
            busy: busy,
            reduced: reduced,
            onConnect: _connect,
            onNewCode: _askForCode,
          ),
          _Mode.wifi when rebooting => const _Rebooting(
            key: ValueKey('rebooting'),
          ),
          _Mode.wifi => _Form(
            key: const ValueKey('form'),
            name: name,
            ssid: _ssid,
            password: _password,
            deviceName: _name,
            error: pairing.error,
            reduced: reduced,
            onPair: () => _pair(host),
          ),
        },
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    super.key,
    required this.name,
    required this.ssid,
    required this.password,
    required this.deviceName,
    required this.onPair,
    required this.reduced,
    this.error,
  });

  final String name;
  final TextEditingController ssid;
  final TextEditingController password;
  final TextEditingController deviceName;
  final VoidCallback onPair;
  final bool reduced;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.form),
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            StepHeader(
              label: '// 03 · Pair · $name',
              title: 'Hand it your network.',
              emphasis: 'network',
              lead:
                  'Orion joins your Wi-Fi, reboots, and comes back on the '
                  'home network in about a minute.',
              reduced: reduced,
            ),
            const SizedBox(height: Space.lg),
            OrionTextField(
              controller: ssid,
              label: '// Wi-Fi name',
              hint: 'Your 2.4 GHz network',
              autofocus: true,
            ),
            const SizedBox(height: Space.md),
            OrionTextField(
              controller: password,
              label: '// Wi-Fi password',
              hint: 'Leave empty for an open network',
              obscure: true,
            ),
            const SizedBox(height: Space.md),
            OrionTextField(
              controller: deviceName,
              label: '// Device name',
              hint: 'Orion',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onPair(),
            ),
            if (error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                '$error'.replaceFirst(RegExp(r'^\w+: '), ''),
                style: context.text.uiSmall,
              ),
            ],
            const SizedBox(height: Space.lg),
            OrionButton(
              label: 'Pair',
              trailingArrow: true,
              expand: true,
              onPressed: onPair,
            ),
          ],
        ),
      ),
    );
  }
}

class _Asking extends StatelessWidget {
  const _Asking({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MonoLabel.eyebrow('Asking Orion for a code'),
          const SizedBox(height: Space.sm),
          Text(
            'Look at its screen.',
            style: context.text.title,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CodeForm extends StatelessWidget {
  const _CodeForm({
    super.key,
    required this.name,
    required this.code,
    required this.busy,
    required this.reduced,
    required this.onConnect,
    required this.onNewCode,
    this.error,
  });

  final String name;
  final TextEditingController code;
  final bool busy;
  final bool reduced;
  final VoidCallback onConnect;
  final VoidCallback onNewCode;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final problem = error == null
        ? null
        : '$error'.replaceFirst(RegExp(r'^\w+: '), '');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OrionContainer.form),
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          shrinkWrap: true,
          children: [
            StepHeader(
              label: '// 03 · Pair · $name',
              title: 'Read me the code.',
              emphasis: 'code',
              lead:
                  '$name shows six digits on its screen for two minutes. They '
                  'prove you are standing next to it.',
              reduced: reduced,
            ),
            const SizedBox(height: Space.lg),
            OrionTextField(
              controller: code,
              label: '// Code',
              hint: '000000',
              mono: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => onConnect(),
              error: problem,
            ),
            const SizedBox(height: Space.lg),
            OrionButton(
              label: 'Connect',
              trailingArrow: true,
              expand: true,
              isLoading: busy,
              onPressed: busy ? null : onConnect,
            ),
            const SizedBox(height: Space.sm),
            OrionButton.ghost(
              label: 'Show a new code',
              expand: true,
              onPressed: busy ? null : onNewCode,
            ),
          ],
        ),
      ),
    );
  }
}

class _Rebooting extends StatelessWidget {
  const _Rebooting({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MonoLabel.eyebrow('Orion is rebooting'),
          const SizedBox(height: Space.sm),
          Text(
            'Waiting for it on the home network.',
            style: context.text.title,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
