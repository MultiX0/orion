import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/local_address.dart';
import '../../../core/platform/platform_info.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../../device/data/device_providers.dart';
import '../../providers/data/llm_providers.dart';
import '../../providers/data/providers_config_notifier.dart';
import '../../providers/domain/llm_provider.dart';
import '../domain/agent_runtime.dart';
import '../domain/confirmation_request.dart';
import '../domain/harness_call.dart';
import '../domain/harness_repository.dart';
import '../domain/harness_status.dart';
import 'confirmation_queue.dart';
import 'dsh_paths_provider.dart';
import 'desktop_harness_repository.dart';
import 'dsh/dsh_probe.dart';
import 'dsh/dsh_runtime.dart';
import 'dsh/null_runtime.dart';
import 'fake_harness_repository.dart';
import 'native_tools/desktop_control.dart';
import 'native_tools/native_tools_factory.dart';
import 'native_tools/windows_firewall.dart';
import 'null_harness_repository.dart';
import 'pc_memory.dart';
import 'phone_brain_host.dart';
import 'tool_executor.dart';
import 'tool_log.dart';
import '../domain/approval_mode.dart';

part 'harness_providers.g.dart';

@Riverpod(keepAlive: true)
AgentRuntime agentRuntime(Ref ref) {
  if (!ref.watch(platformInfoProvider).canHostHarness) {
    return const NullRuntime();
  }
  return DshRuntime(paths: ref.watch(dshPathsProvider), probe: DshProbe());
}

/// The real harness on desktop, a polite no on a phone, the fake in tests.
@Riverpod(keepAlive: true)
HarnessRepository harnessRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) {
    final fake = FakeHarnessRepository();
    ref.onDispose(fake.dispose);
    return fake;
  }
  final info = ref.watch(platformInfoProvider);
  if (!info.canHostHarness) {
    return NullHarnessRepository(
      deviceClient: ref.watch(deviceClientProvider),
      approvalMode: ref.watch(approvalModeProvider),
      saveApprovalMode: (mode) =>
          ref.read(appSettingsProvider.notifier).setApprovalMode(mode),
    );
  }

  final queue = ConfirmationQueue();
  final agent = ref.watch(agentRuntimeProvider);
  final control = DesktopControl.isSupported ? DesktopControl() : null;
  late final DesktopHarnessRepository repo;
  final executor = ToolExecutor(
    control: control,
    tools: nativeToolsFor(info.osName),
    agent: agent,
    queue: queue,
    brain: () => _currentBrain(ref),
    localApproval: () => repo.approvalMode,
    // Read, not watched: the board connection rebuilds these, and each
    // rebuild would make a second harness whose server finds port 7331
    // still held by the first.
    describe: ref.read(providerRepositoryProvider),
    onUpdate: (call) => repo.record(call),
    onAgentLog: (jobId, line) => repo.recordAgentLog(jobId, line),
  );
  repo = DesktopHarnessRepository(
    executor: executor,
    queue: queue,
    agent: agent,
    deviceClient: ref.read(deviceClientProvider),
    liveClient: () => ref.read(deviceClientProvider),
    log: ToolLog(ref.watch(dshPathsProvider).toolLogFile),
    boardHost: () => ref.read(pairedDeviceProvider)?.host,
    saveApprovalMode: (mode) =>
        ref.read(appSettingsProvider.notifier).setApprovalMode(mode),
    // The board's turns run here when PC control is on, with the same model
    // and key the user picked in Providers.
    brain: () => _currentBrain(ref),
    // What was said and done, on disk, and what is open right now.
    memory: PcMemory(),
    desktopState: control?.openWindows,
    // One Windows consent prompt the first time PC control goes on.
    allowInbound: Platform.isWindows
        ? (port) async =>
              await WindowsFirewall.isAllowed(port) ||
              await WindowsFirewall.allow(port)
        : null,
  );
  ref.onDispose(repo.dispose);
  unawaited(_boot(ref, repo));
  return repo;
}

Future<void> _boot(Ref ref, DesktopHarnessRepository repo) async {
  // The server refuses everything until the keychain answers, which is the
  // right default for a port on the LAN.
  final secrets = ref.read(secretStoreProvider);
  // Waited for, not peeked at: read at once it is still loading at launch,
  // and PC control that was on when the app closed would stay off.
  final settings = await ref.read(appSettingsProvider.future);
  if (!ref.mounted) return;
  final config = ref.read(providersConfigProvider);
  repo.pairingToken = await secrets.read(SecretKeys.pairingToken);
  repo.seedApprovalMode(settings.approvalMode);
  // The server before the version probe: the board can send a turn at any
  // moment, and asking dsh and Node for their versions takes seconds.
  if (settings.harnessEnabled) {
    // A server that could not start now (the port still closing, the network
    // not up yet) tries again, so PC control never stays off by itself.
    for (var attempt = 0; attempt < 6 && ref.mounted; attempt++) {
      if ((await repo.setEnabled(true)).isOk) break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  final selected = config.providers
      .where((p) => p.id == config.selectedId)
      .firstOrNull;
  await repo.refreshStatus(
    providerName: selected?.name,
    model: selected?.selectedModel,
  );
  await repo.loadApprovalFromBoard();
}

/// The phone lends the board its brain while the app runs and holds its link:
/// a turn goes to this phone's model, with the web, the date and what was said
/// before, and the board speaks the answer. The value is the address the board
/// is told, "192.168.1.23:7331"; null on desktop (the PC has PC control), in
/// tests, before pairing, or when the phone would not open the port.
@Riverpod(keepAlive: true)
Future<String?> phoneBrain(Ref ref) async {
  final info = ref.watch(platformInfoProvider);
  if (!info.isMobile || ref.watch(useFakesProvider)) return null;
  final board = ref.watch(pairedDeviceProvider)?.host;
  if (board == null) return null;
  final token = await ref
      .read(secretStoreProvider)
      .read(SecretKeys.pairingToken);
  final dir = await getApplicationSupportDirectory();
  final host = PhoneBrainHost(
    brain: () => _currentBrain(ref),
    token: () => token,
    memory: PcMemory(
      file: File('${dir.path}${Platform.pathSeparator}memory.json'),
    ),
  );
  ref.onDispose(host.stop);
  final port = await host.start();
  if (port == null) return null;
  // Android freezes an app another app has covered, and "open YouTube" does
  // exactly that. A foreground service keeps the brain answering.
  if (Platform.isAndroid) {
    const service = MethodChannel('orion/brain_service');
    unawaited(service.invokeMethod<bool>('start').catchError((_) => false));
    ref.onDispose(
      () => unawaited(
        service.invokeMethod<bool>('stop').catchError((_) => false),
      ),
    );
  }
  // An emulator sits behind its own NAT: `adb forward` plus a relay on the
  // host make it reachable, and this says where.
  const forced = String.fromEnvironment('ORION_BRAIN_ADDR');
  if (forced.isNotEmpty) return forced;
  final url = await LocalAddress.baseUrlFor(port: port, boardHost: board);
  return url?.replaceFirst('http://', '');
}

/// The provider and model the harness borrows, with the key attached.
Future<(LlmProvider, String)?> _currentBrain(Ref ref) async {
  if (!ref.mounted) return null;
  final config = ref.read(providersConfigProvider);
  final secrets = ref.read(secretStoreProvider);
  final provider = config.providers
      .where((p) => p.id == config.selectedId)
      .firstOrNull;
  // The fast model: the brain moves a turn to provider.thinkingModel itself
  // the moment it has to act on the PC or phone.
  final model = provider?.selectedModel;
  if (provider == null || model == null) return null;
  final key = await secrets.read(SecretKeys.providerApiKey(provider.id));
  return (provider.copyWith(apiKey: key), model);
}

@Riverpod(keepAlive: true)
Stream<HarnessStatus> harnessStatus(Ref ref) =>
    ref.watch(harnessRepositoryProvider).status;

@Riverpod(keepAlive: true)
Stream<List<HarnessCall>> harnessFeed(Ref ref) =>
    ref.watch(harnessRepositoryProvider).feed;

@Riverpod(keepAlive: true)
Stream<List<ConfirmationRequest>> pendingConfirmations(Ref ref) =>
    ref.watch(harnessRepositoryProvider).pending;

/// The local copy of pc.approval. The board's config is the source of truth;
/// every write to the board updates this copy too.
@Riverpod(keepAlive: true)
ApprovalMode approvalMode(Ref ref) =>
    ref.watch(appSettingsProvider.select((s) => s.value?.approvalMode)) ??
    ApprovalMode.ask;
