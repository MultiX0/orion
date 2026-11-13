import 'dart:io';

import '../../../../core/result.dart';
import '../../../providers/domain/llm_provider.dart';
import '../../../providers/domain/provider_kind.dart';
import 'dsh_paths.dart';

/// Writes what dsh reads for the agent: the headless profile's own patch
/// layer (`profiles/headless/cordis.patch.yml`) with the provider, the model
/// and, with desktop control, the tools that drive the computer; and `.env`
/// with the key. docs/HARNESS.md, "The PC agent", has the why.
///
/// Desktop control is MCP servers, which dsh's own MCP client runs:
/// Playwright for anything in a browser (a visible window, by the page's own
/// elements), and on Windows winapp for applications (UI Automation, by
/// their controls). Elsewhere Cua Driver drives applications instead; it is a
/// dsh plugin and is installed into the profile once. Every server and
/// plugin is pinned to an exact version; npm resolves their own
/// dependencies on first fetch.
///
/// dsh 0.2.2 applies a profile's `cordis.patch.yml` after every bundle
/// layer. The `settings.yaml` this used to write was not applied reliably:
/// with a profile patch present the agent fell back to DeepSeek's own model.
class DshConfigWriter {
  const DshConfigWriter(this.paths);

  final DshPaths paths;

  /// The environment variable the provider route reads its key from.
  static const apiKeyEnv = 'DP_ORION_KEY';

  /// The route id for a provider dsh's catalog does not know.
  static const providerId = 'orion';

  /// The profile the agent runs in.
  static const profile = 'headless';

  /// Browsers, on every desktop.
  static const playwrightMcp = '@playwright/mcp@0.0.84';

  /// Windows applications, through UI Automation.
  static const winappMcp = 'winapp-mcp@2.0.0';

  /// Applications on macOS and Linux, where winapp does not run.
  static const desktopPlugins = <String>[
    '@deepseek-ai/dsh-computer-use',
    '@deepseek-ai/dsh-experimental-computer-use-cua-driver-native',
  ];

  /// [windows] defaults to the platform this runs on; the runtime passes its
  /// own, so a test of the Windows setup runs anywhere.
  Future<Result<void>> write(
    LlmProvider provider,
    String model, {
    bool desktop = false,
    bool cua = false,
    bool? windows,
  }) async {
    try {
      await paths.ensureDirectories();
      await Directory(paths.profileDir(profile)).create(recursive: true);
      await File(paths.profilePatch(profile)).writeAsString(
        patchYaml(
          provider,
          model,
          desktop: desktop,
          cua: cua,
          windows: windows ?? Platform.isWindows,
          downloads: DshPaths.downloads(),
        ),
      );
      await _writeSecret(provider.apiKey ?? '');
      return const Ok(null);
    } on FileSystemException catch (e) {
      return Err(
        StorageFailure('Could not write the dsh config: ${e.message}'),
      );
    }
  }

  /// The route dsh uses for this provider. Anthropic and OpenAI go through
  /// dsh's own catalog routes, which know each model's limits and that it
  /// sees images (desktop control sends screenshots). Anything else is an
  /// OpenAI style route of our own, declared as seeing images.
  static String routeFor(LlmProvider provider) => switch (provider.kind) {
    ProviderKind.anthropic => 'anthropic',
    ProviderKind.openai => 'openai',
    _ => providerId,
  };

  /// A pure function so the shape is a test, not a guess. [cua] adds Cua
  /// Driver (installed into the profile first); [windows] picks winapp and
  /// Edge; [downloads] is where browser files land.
  static String patchYaml(
    LlmProvider provider,
    String model, {
    bool desktop = false,
    bool cua = false,
    bool windows = false,
    String downloads = '',
  }) {
    final route = routeFor(provider);
    final b = StringBuffer()
      ..writeln('# Written by Orion. Edit the provider in the app, not here.')
      ..writeln('- id: llm-pi-ai')
      ..writeln('  config:')
      ..writeln('    providers:')
      ..writeln('      $route:')
      ..writeln('        apiKeyEnv: $apiKeyEnv');
    if (route == providerId) {
      b
        ..writeln('        api: openai-completions')
        ..writeln('        baseURL: ${_scalar(provider.baseUrl)}')
        ..writeln('        models:')
        ..writeln('          - id: ${_scalar(model)}')
        ..writeln('            input: [text, image]');
    } else if (route == 'openai' &&
        provider.baseUrl.isNotEmpty &&
        provider.baseUrl != 'https://api.openai.com/v1') {
      b.writeln('        baseURL: ${_scalar(provider.baseUrl)}');
    }
    b
      ..writeln('- id: agent-default-model')
      ..writeln('  config:')
      ..writeln('    provider: $route')
      ..writeln('    model: ${_scalar(model)}');
    if (desktop) {
      b
        ..writeln('- insert:')
        ..write(
          _mcp('playwright', <String>[
            playwrightMcp,
            // Edge is on every Windows PC; elsewhere the Chrome Playwright
            // finds. Headed: the user watches it work.
            '--browser',
            windows ? 'msedge' : 'chrome',
            if (downloads.isNotEmpty) ...<String>['--output-dir', downloads],
          ]),
        );
      if (windows) b.write(_mcp('winapp', <String>[winappMcp]));
      if (cua) {
        b
          ..writeln('    - id: computer-use')
          ..writeln("      name: '${desktopPlugins[0]}'")
          ..writeln('    - id: computer-use-cua-driver')
          ..writeln("      name: '${desktopPlugins[1]}'");
      }
    }
    return b.toString();
  }

  /// One MCP server through `npx -y`, started by dsh's MCP client. The first
  /// start downloads the package, hence the long startup budget.
  static String _mcp(String server, List<String> args) =>
      '    - id: mcp-$server\n'
      "      name: '@deepseek-ai/dsh-mcp-client'\n"
      '      config:\n'
      '        serverName: $server\n'
      '        transport: stdio\n'
      '        command: npx\n'
      "        args: [${['-y', ...args].map(_scalar).join(', ')}]\n"
      '        startupTimeoutMs: 180000\n'
      '        toolCallTimeoutMs: 120000\n';

  static String envFileBody(String apiKey) => '$apiKeyEnv=$apiKey\n';

  /// Single quotes, with internal quotes doubled. Model ids carry slashes,
  /// colons and dots, and a bare scalar would eventually lose that argument.
  static String _scalar(String value) => "'${value.replaceAll("'", "''")}'";

  Future<void> _writeSecret(String apiKey) async {
    final file = File(paths.envFile);
    await file.writeAsString(envFileBody(apiKey));
    // The key is in here. Nobody else on the machine needs to read it.
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }
}
