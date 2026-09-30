import 'dart:convert';
import 'dart:io';

import '../domain/harness_call.dart';

/// Every tool call, one JSON object per line, in ~/Orion/logs/tools.jsonl.
/// Required by docs/HARNESS.md. Writes never throw: a full disk must not
/// stop the board from getting an answer.
class ToolLog {
  const ToolLog(this.path);

  final String path;

  Future<void> append(HarnessCall call) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(line(call))}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      return;
    }
  }

  /// Pure, so the shape is a test. No keys reach here: tool arguments come
  /// from the board's LLM and never carry a provider key.
  static Map<String, dynamic> line(HarnessCall call) => <String, dynamic>{
    'ts': DateTime.now().toUtc().toIso8601String(),
    'call_id': call.callId,
    if (call.turnId != null) 'turn_id': call.turnId,
    'name': call.name,
    'args': call.args,
    'status': call.status.name,
    'approval': call.approvalMode.name,
    if (call.approvedBy != null) 'approved_by': call.approvedBy,
    if (call.result != null) 'result': _clip(call.result!),
    if (call.message != null) 'message': _clip(call.message!),
  };

  /// A screenshot description or an agent transcript can be long. The log is
  /// for "what happened", not for the whole answer.
  static String _clip(String value) =>
      value.length <= 500 ? value : '${value.substring(0, 500)}...';
}
