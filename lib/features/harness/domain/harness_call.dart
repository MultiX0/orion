import 'package:freezed_annotation/freezed_annotation.dart';

import 'approval_mode.dart';
import 'harness_call_status.dart';

part 'harness_call.freezed.dart';
part 'harness_call.g.dart';

/// One POST /tool from the board and what happened to it.
@freezed
abstract class HarnessCall with _$HarnessCall {
  const factory HarnessCall({
    required String callId,
    required String name,
    required DateTime receivedAt,
    String? turnId,
    @Default(<String, dynamic>{}) Map<String, dynamic> args,
    @Default(HarnessCallStatus.pending) HarnessCallStatus status,
    String? result,
    String? message,
    String? confirmId,
    String? jobId,

    /// "user", "session" or "policy" when the mode let it run unasked.
    String? approvedBy,

    /// The mode this call ran under, so the feed and the log can say so.
    @Default(ApprovalMode.ask) ApprovalMode approvalMode,
  }) = _HarnessCall;

  factory HarnessCall.fromJson(Map<String, dynamic> json) =>
      _$HarnessCallFromJson(json);
}
