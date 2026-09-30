import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../../providers/domain/llm_provider.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import '../domain/tool_request.dart';
import '../domain/tool_safety.dart';
import '../domain/tool_spec.dart';
import 'pc_brain.dart';
import 'pc_memory.dart';
import 'tool_server.dart';

/// The phone as an extended brain. While the app runs and holds its link to
/// the board, the board sends its turns here instead of to its own model:
/// this phone's model and key, the web, the date, the conversation it
/// remembers, and links it can open on the phone. The board still wakes on
/// its word, listens, shows the orb and speaks; the phone only writes the
/// words. The same server and brain as the PC's, with the phone's one tool.
class PhoneBrainHost {
  PhoneBrainHost({
    required Future<(LlmProvider, String)?> Function() brain,
    required String? Function() token,
    PcMemory? memory,
    Future<bool> Function(Uri uri)? launch,
    int port = ToolServer.defaultPort,
  }) : _launch = launch ?? _launchOutside {
    final pcBrain = PcBrain(
      brain: brain,
      catalog: () async => const [openLink],
      runTool: _run,
      updates: _updates.stream,
      memory: memory,
      onPhone: true,
    );
    server = ToolServer(
      catalog: () async => const [openLink],
      start: _run,
      lookup: (_) => null,
      updates: _updates.stream,
      agentLogs: const Stream.empty(),
      token: token,
      chat: pcBrain.open,
      port: port,
    );
  }

  late final ToolServer server;
  final Future<bool> Function(Uri uri) _launch;
  final _updates = StreamController<HarnessCall>.broadcast();

  static const openLink = ToolSpec(
    name: 'open_link',
    description:
        'Open a web address or an app link on this phone. App links act inside '
        'the app: spotify:track:<id> opens that song in Spotify, '
        'spotify:search:<words> searches Spotify, https:// opens the browser, '
        'geo:0,0?q=<place> opens the map, mailto: starts an email.',
    safety: ToolSafety.safe,
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'target': <String, dynamic>{
          'type': 'string',
          'description': 'The address or app link',
        },
      },
      'required': <String>['target'],
    },
  );

  static Future<bool> _launchOutside(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// The port it listens on, or null when the phone would not open one.
  Future<int?> start() async {
    try {
      await server.startServer();
      return server.boundPort;
    } on Object {
      return null;
    }
  }

  Future<void> stop() async {
    await server.stopServer();
    await _updates.close();
  }

  Future<HarnessCall> _run(ToolRequest request) async {
    final call = HarnessCall(
      callId: request.callId,
      turnId: request.turnId,
      name: request.name,
      args: request.args,
      receivedAt: DateTime.now(),
    );
    if (request.name != openLink.name) {
      return call.copyWith(
        status: HarnessCallStatus.error,
        message: 'The phone has no tool called ${request.name}.',
      );
    }
    final target = '${request.args['target'] ?? ''}'.trim();
    final uri = Uri.tryParse(target);
    if (target.isEmpty || uri == null || !uri.hasScheme) {
      return call.copyWith(
        status: HarnessCallStatus.error,
        message: 'Nothing to open.',
      );
    }
    var opened = false;
    try {
      opened = await _launch(uri);
    } on Object {
      opened = false;
    }
    return call.copyWith(
      status: opened ? HarnessCallStatus.done : HarnessCallStatus.error,
      result: opened ? 'Opened $target on the phone.' : null,
      message: opened ? null : 'The phone has nothing that opens $target.',
    );
  }
}
