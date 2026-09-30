import 'package:json_annotation/json_annotation.dart';

/// What the board is doing right now. The orb maps this directly.
@JsonEnum(fieldRename: FieldRename.snake)
enum DeviceMode { idle, listening, thinking, speaking, error, offline }
