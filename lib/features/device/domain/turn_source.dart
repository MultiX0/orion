import 'package:json_annotation/json_annotation.dart';

/// What started a turn.
@JsonEnum(fieldRename: FieldRename.snake)
enum TurnSource { wake, button, app, appSnapshot }
