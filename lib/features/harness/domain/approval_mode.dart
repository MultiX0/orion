import 'package:json_annotation/json_annotation.dart';

/// Whether the desktop asks before a risky tool runs. Lives in the board
/// config as pc.approval so the phone, the PC and the board agree.
@JsonEnum(fieldRename: FieldRename.snake)
enum ApprovalMode {
  /// Safe tools run at once, the rest wait for the user.
  ask,

  /// Everything runs the moment it arrives, agent tasks included.
  auto,
}
