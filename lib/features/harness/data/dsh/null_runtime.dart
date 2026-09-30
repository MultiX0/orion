import '../../../providers/domain/llm_provider.dart';
import '../../domain/agent_runtime.dart';

/// No Node, no dsh, or a phone. `agent_task` is left out of GET /tools, so
/// the LLM never learns the tool exists and nothing here is ever called.
class NullRuntime implements AgentRuntime {
  const NullRuntime({this.node});

  /// Node may be installed and still be too old. The header says which.
  final String? node;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<AgentVersions> versions() async => AgentVersions(node: node);

  @override
  Future<AgentJob> run(
    String task, {
    required LlmProvider provider,
    required String model,
  }) async => AgentJob(
    id: 'none',
    task: task,
    done: Future<AgentResult>.value(
      const AgentResult(
        ok: false,
        text: 'Agent tasks need Node 22.19 or newer on this PC',
      ),
    ),
  );

  @override
  Stream<String> logs(String jobId) => const Stream<String>.empty();

  @override
  Future<void> cancel(String jobId) async {}
}
