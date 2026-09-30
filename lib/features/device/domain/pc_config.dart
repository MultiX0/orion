import 'package:freezed_annotation/freezed_annotation.dart';
import '../../harness/domain/approval_mode.dart';

part 'pc_config.freezed.dart';
part 'pc_config.g.dart';

/// The pc block of the board config: where the desktop harness lives.
/// Every field is nullable because this is also a patch: a phone changing
/// the approval mode must not switch PC control off on its way past.
@freezed
abstract class PcConfig with _$PcConfig {
  const PcConfig._();

  const factory PcConfig({
    bool? enabled,
    String? baseUrl,
    String? token,

    /// Whether the desktop asks before a risky tool. Null leaves it as is.
    ApprovalMode? approval,
  }) = _PcConfig;

  bool get isEnabled => enabled ?? false;

  factory PcConfig.fromJson(Map<String, dynamic> json) =>
      _$PcConfigFromJson(json);
}
