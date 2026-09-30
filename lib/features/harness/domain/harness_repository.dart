import '../../../core/result.dart';
import 'confirmation_request.dart';
import 'harness_call.dart';
import 'harness_status.dart';
import 'approval_mode.dart';

/// The desktop PC-control layer as the Harness screen sees it.
abstract class HarnessRepository {
  Stream<HarnessStatus> get status;

  /// Every call this session, newest first.
  Stream<List<HarnessCall>> get feed;

  Stream<List<ConfirmationRequest>> get pending;

  /// Starts or stops the tool server and tells the board.
  Future<Result<void>> setEnabled(bool enabled);

  /// Writes pc.approval on the board and keeps a local copy.
  Future<Result<void>> setApprovalMode(ApprovalMode mode);

  Future<void> approve(String confirmId, {bool alwaysAllowThisSession = false});

  Future<void> deny(String confirmId);
}
