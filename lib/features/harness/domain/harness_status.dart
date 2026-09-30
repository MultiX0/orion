import 'package:freezed_annotation/freezed_annotation.dart';
import 'approval_mode.dart';

part 'harness_status.freezed.dart';

/// What the Harness screen header shows.
@freezed
abstract class HarnessStatus with _$HarnessStatus {
  const factory HarnessStatus({
    @Default(false) bool isEnabled,
    @Default(ApprovalMode.ask) ApprovalMode approvalMode,
    @Default(false) bool isServerRunning,

    /// "192.168.1.20:7331" when listening.
    String? serverAddress,
    @Default(false) bool isDshAvailable,
    String? dshVersion,
    String? nodeVersion,
    String? providerName,
    String? model,
  }) = _HarnessStatus;
}
