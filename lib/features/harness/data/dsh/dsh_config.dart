import 'dart:io';

import '../../../../core/result.dart';
import '../../../providers/domain/llm_provider.dart';
import 'dsh_paths.dart';

/// Writes the two files dsh actually reads: `settings.yaml` for the provider
/// and the default model, `.env` for the key. The dsh section of
/// docs/HARNESS.md says where those names come from.
class DshConfigWriter {
  const DshConfigWriter(this.paths);

  final DshPaths paths;

  /// The environment variable name dsh resolves through `apiKeyEnv`. Custom
  /// providers use the DP_ prefix.
  static const apiKeyEnv = 'DP_ORION_KEY';

  /// The provider id inside dsh. Ours is always the one Orion mirrors.
  static const providerId = 'orion';

  Future<Result<void>> write(LlmProvider provider, String model) async {
    try {
      await paths.ensureDirectories();
      await File(
        paths.settingsFile,
      ).writeAsString(settingsYaml(provider.baseUrl, model));
      await _writeSecret(provider.apiKey ?? '');
      return const Ok(null);
    } on FileSystemException catch (e) {
      return Err(
        StorageFailure('Could not write the dsh config: ${e.message}'),
      );
    }
  }

  /// A pure function so the shape is a test, not a guess.
  static String settingsYaml(String baseUrl, String model) =>
      '''
# Written by Orion. Edit the provider in the app, not here.
llm-pi-ai:
  providers:
    $providerId:
      api: openai-completions
      baseURL: ${_scalar(baseUrl)}
      apiKeyEnv: $apiKeyEnv
      models:
        - id: ${_scalar(model)}
agent-default-model:
  provider: $providerId
  model: ${_scalar(model)}
''';

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
