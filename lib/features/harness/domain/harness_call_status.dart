import 'package:json_annotation/json_annotation.dart';

/// Status of a tool call on the desktop, as the board sees it.
@JsonEnum(fieldRename: FieldRename.snake)
enum HarnessCallStatus {
  pending,
  pendingConfirmation,
  running,
  done,
  error,
  denied,
}
