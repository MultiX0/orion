import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_stats.freezed.dart';
part 'system_stats.g.dart';

/// What `system_stats` reports back. Every field is optional because no OS
/// gives us all of them, and a missing GPU is not a failure.
@freezed
abstract class SystemStats with _$SystemStats {
  const SystemStats._();

  const factory SystemStats({
    double? cpuPct,
    double? memUsedGb,
    double? memTotalGb,
    double? gpuPct,
    double? gpuTempC,
    double? cpuTempC,
    String? gpuName,
  }) = _SystemStats;

  factory SystemStats.fromJson(Map<String, dynamic> json) =>
      _$SystemStatsFromJson(json);

  /// One line for the board to read out loud.
  String get spoken {
    final parts = <String>[
      if (cpuPct != null) 'CPU ${cpuPct!.round()} percent',
      if (memUsedGb != null && memTotalGb != null)
        'RAM ${memUsedGb!.toStringAsFixed(1)} of '
            '${memTotalGb!.toStringAsFixed(1)} gigabytes',
      if (gpuName != null && gpuPct != null)
        '$gpuName at ${gpuPct!.round()} percent',
      if (gpuTempC != null) 'GPU ${gpuTempC!.round()} degrees',
      if (cpuTempC != null) 'CPU ${cpuTempC!.round()} degrees',
    ];
    return parts.isEmpty ? 'No readings available' : parts.join(', ');
  }
}
