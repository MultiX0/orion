// Orion's PC side without the window: the same tool server, tools and PC brain
// the desktop app runs when PC control is on, from the command line. It tells
// the paired board where it is, then serves until Ctrl+C.
//
//   dart run tool/pc_harness.dart <board ip> [token file]
//
// Reads DEEPINFRA_API_KEY and LLM_MODEL from .env and the board's pairing
// token from logs/ble_pair_token.txt by default. Prints neither. Approval mode
// is ask: anything risky waits for approval, and with no window to approve in,
// the board is told it is waiting.
import 'dart:async';
import 'dart:io';

import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/network/local_address.dart';
import 'package:orion/features/device/data/http_device_client.dart';
import 'package:orion/features/device/domain/device_config.dart';
import 'package:orion/features/device/domain/pc_config.dart';
import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/native_tools/desktop_control.dart';
import 'package:orion/features/harness/data/native_tools/native_tools_factory.dart';
import 'package:orion/features/harness/data/native_tools/windows_firewall.dart';
import 'package:orion/features/harness/data/pc_brain.dart';
import 'package:orion/features/harness/data/pc_memory.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/data/tool_server.dart';
import 'package:orion/features/harness/domain/approval_mode.dart';
import 'package:orion/features/harness/domain/harness_call.dart';
import 'package:orion/features/providers/data/http_provider_repository.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

String _env(String key, [String fallback = '']) {
  for (final line in File('.env').readAsLinesSync()) {
    if (line.startsWith('$key=')) return line.substring(key.length + 1).trim();
  }
  return fallback;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/pc_harness.dart <board ip> [token file]',
    );
    exit(64);
  }
  final boardHost = args[0];
  final token = File(
    args.length > 1 ? args[1] : 'logs/ble_pair_token.txt',
  ).readAsStringSync().trim();
  final provider = LlmProvider(
    id: 'deepinfra',
    kind: ProviderKind.deepinfra,
    name: 'DeepInfra',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    apiKey: _env('DEEPINFRA_API_KEY'),
  );
  final model = _env('LLM_MODEL', 'google/gemma-4-31B-it-turbo');
  Future<(LlmProvider, String)?> brain() async => (provider, model);

  final board = HttpDeviceClient(
    api: DeviceApi(host: boardHost, token: token),
  );
  final updates = StreamController<HarnessCall>.broadcast();
  final calls = <String, HarnessCall>{};
  final control = DesktopControl.isSupported ? DesktopControl() : null;
  final executor = ToolExecutor(
    control: control,
    tools: nativeToolsFor(Platform.operatingSystem),
    agent: const NullRuntime(),
    queue: ConfirmationQueue(),
    brain: brain,
    localApproval: () => ApprovalMode.ask,
    describe: HttpProviderRepository(deviceClient: board),
    onUpdate: (call) {
      calls[call.callId] = call;
      updates.add(call);
      stdout.writeln('[tool] ${call.name} ${call.args} -> ${call.status.name}');
    },
    onAgentLog: (_, _) {},
  );
  final pcBrain = PcBrain(
    brain: brain,
    catalog: executor.catalog,
    runTool: executor.start,
    updates: updates.stream,
    memory: PcMemory(),
    desktopState: control?.openWindows,
  );
  final server = ToolServer(
    catalog: executor.catalog,
    start: executor.start,
    lookup: (id) => calls[id],
    updates: updates.stream,
    agentLogs: const Stream.empty(),
    token: () => token,
    chat: (body) async {
      final q = (body['messages'] as List?)?.lastOrNull;
      stdout.writeln('[board] ${q is Map ? q['content'] : ''}');
      return pcBrain.open(body);
    },
  );
  await server.startServer();
  if (Platform.isWindows) {
    final port = server.boundPort ?? ToolServer.defaultPort;
    final open =
        await WindowsFirewall.isAllowed(port) ||
        await WindowsFirewall.allow(port);
    stdout.writeln(
      'firewall: ${open ? 'open to the local network' : 'blocked, say Yes in the Windows prompt'}',
    );
  }
  final url = await LocalAddress.baseUrlFor(
    port: server.boundPort ?? ToolServer.defaultPort,
    boardHost: boardHost,
  );
  stdout.writeln('PC brain listening, telling the board: $url');
  final told = await board.updateConfig(
    DeviceConfig(
      pc: PcConfig(enabled: true, baseUrl: url, token: token),
    ),
  );
  stdout.writeln('board config: ${told.isOk ? 'ok' : told}');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stopServer();
    exit(0);
  });
}
