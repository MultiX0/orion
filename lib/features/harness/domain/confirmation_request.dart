import 'package:freezed_annotation/freezed_annotation.dart';

import 'harness_call.dart';

part 'confirmation_request.freezed.dart';

/// A tool call waiting for the user to approve or deny it.
@freezed
abstract class ConfirmationRequest with _$ConfirmationRequest {
  const factory ConfirmationRequest({
    required String id,
    required HarnessCall toolCall,
    required DateTime requestedAt,

    /// False for agent_task, which asks every single time.
    @Default(true) bool canAlwaysAllow,
  }) = _ConfirmationRequest;
}
