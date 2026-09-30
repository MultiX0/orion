import 'package:freezed_annotation/freezed_annotation.dart';

part 'file_hit.freezed.dart';
part 'file_hit.g.dart';

/// One result from `search_files`.
@freezed
abstract class FileHit with _$FileHit {
  const factory FileHit({
    required String name,
    required String path,
    int? sizeBytes,
    DateTime? modifiedAt,
  }) = _FileHit;

  factory FileHit.fromJson(Map<String, dynamic> json) =>
      _$FileHitFromJson(json);
}
