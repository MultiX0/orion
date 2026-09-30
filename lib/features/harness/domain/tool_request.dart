import 'package:freezed_annotation/freezed_annotation.dart';

import 'approval_mode.dart';
import 'harness_call_status.dart';

part 'tool_request.freezed.dart';
part 'tool_request.g.dart';

/// The body of POST /tool, exactly as docs/HARNESS.md defines it.
@freezed
abstract class ToolRequest with _$ToolRequest {
  const factory ToolRequest({
    required String callId,
    required String name,
    String? turnId,
    @Default(<String, dynamic>{}) Map<String, dynamic> args,

    /// The board's pc.approval for this call. Missing on an older board,
    /// and then the desktop's own copy decides.
    ApprovalMode? approval,
  }) = _ToolRequest;

  factory ToolRequest.fromJson(Map<String, dynamic> json) =>
      _$ToolRequestFromJson(json);
}

/// The answer to POST /tool and GET /tool/:id. Null fields are left out of
/// the JSON, so each status carries only its own field.
@freezed
abstract class ToolOutcome with _$ToolOutcome {
  const factory ToolOutcome({
    required HarnessCallStatus status,
    String? result,
    String? message,
    String? confirmId,
    String? jobId,
  }) = _ToolOutcome;

  factory ToolOutcome.done(String result) =>
      ToolOutcome(status: HarnessCallStatus.done, result: result);

  factory ToolOutcome.error(String message) =>
      ToolOutcome(status: HarnessCallStatus.error, message: message);

  factory ToolOutcome.denied() => const ToolOutcome(
    status: HarnessCallStatus.denied,
    message: 'denied by user',
  );

  factory ToolOutcome.waiting(String confirmId) => ToolOutcome(
    status: HarnessCallStatus.pendingConfirmation,
    confirmId: confirmId,
  );

  factory ToolOutcome.running(String jobId) =>
      ToolOutcome(status: HarnessCallStatus.running, jobId: jobId);

  factory ToolOutcome.fromJson(Map<String, dynamic> json) =>
      _$ToolOutcomeFromJson(json);
}
