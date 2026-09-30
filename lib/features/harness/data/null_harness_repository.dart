import '../../../core/result.dart';
import '../../device/domain/device_client.dart';
import '../../device/domain/device_config.dart';
import '../../device/domain/pc_config.dart';
import '../domain/confirmation_request.dart';
import '../domain/harness_call.dart';
import '../domain/harness_repository.dart';
import '../domain/harness_status.dart';
import '../domain/approval_mode.dart';

/// Phones and anything else that cannot host the harness. The route is not
/// built there, but a provider that exists and says "no" beats one that
/// throws the first time something reads it.
class NullHarnessRepository implements HarnessRepository {
  const NullHarnessRepository({
    this.deviceClient,
    this.saveApprovalMode,
    this.approvalMode = ApprovalMode.ask,
  });

  /// A phone has no tool server, but it still sets the board's mode.
  final DeviceClient? deviceClient;
  final Future<void> Function(ApprovalMode mode)? saveApprovalMode;
  final ApprovalMode approvalMode;

  @override
  Stream<HarnessStatus> get status =>
      Stream<HarnessStatus>.value(HarnessStatus(approvalMode: approvalMode));

  @override
  Stream<List<HarnessCall>> get feed =>
      Stream<List<HarnessCall>>.value(const <HarnessCall>[]);

  @override
  Stream<List<ConfirmationRequest>> get pending =>
      Stream<List<ConfirmationRequest>>.value(const <ConfirmationRequest>[]);

  @override
  Future<Result<void>> setEnabled(bool enabled) async =>
      const Err(UnsupportedFailure('PC control only runs on a desktop'));

  @override
  Future<Result<void>> setApprovalMode(ApprovalMode mode) async {
    await saveApprovalMode?.call(mode);
    final client = deviceClient;
    if (client == null) return const Ok(null);
    final result = await client.updateConfig(
      DeviceConfig(pc: PcConfig(approval: mode)),
    );
    return switch (result) {
      Err(failure: NetworkFailure()) => const Ok(null),
      _ => result.map((_) {}),
    };
  }

  @override
  Future<void> approve(
    String confirmId, {
    bool alwaysAllowThisSession = false,
  }) async {}

  @override
  Future<void> deny(String confirmId) async {}
}
