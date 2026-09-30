import '../../providers/domain/llm_provider.dart';

/// A long-running agent task. The tool server answers the board with the id
/// and streams the rest, because an agent takes minutes, not seconds.
class AgentJob {
  const AgentJob({required this.id, required this.task, this.done});

  final String id;
  final String task;

  /// Completes with the agent's final answer, or an error line.
  final Future<AgentResult>? done;
}

class AgentResult {
  const AgentResult({required this.ok, required this.text});
  final bool ok;
  final String text;
}

/// Whatever runs open-ended tasks on this PC. dsh today, anything tomorrow.
abstract class AgentRuntime {
  /// Cheap after the first call: the probe result is cached for the session.
  Future<bool> isAvailable();

  /// Node and dsh versions for the Harness header, null when absent.
  Future<AgentVersions> versions();

  Future<AgentJob> run(
    String task, {
    required LlmProvider provider,
    required String model,
  });

  /// Lines as they arrive, oldest first. Closes when the job ends.
  Stream<String> logs(String jobId);

  Future<void> cancel(String jobId);
}

class AgentVersions {
  const AgentVersions({this.node, this.dsh});
  final String? node;
  final String? dsh;

  bool get hasNode => node != null;
  bool get hasDsh => dsh != null;
}
