import 'dart:convert';

import '../../domain/system_stats.dart';

/// Turns the raw output of the stats commands into numbers. Pure functions,
/// so every one of them has a fixture test instead of a running PC.
abstract final class StatsParsers {
  /// PowerShell writes one object: { Cpu, FreeKb, TotalKb }. ConvertTo-Json
  /// emits a bare object, and an array if the caller ever asks for more.
  static SystemStats windows(String json) {
    final decoded = _firstObject(json);
    if (decoded == null) return const SystemStats();
    final freeKb = _num(decoded['FreeKb']);
    final totalKb = _num(decoded['TotalKb']);
    final used = (freeKb != null && totalKb != null)
        ? (totalKb - freeKb) / 1048576
        : null;
    return SystemStats(
      cpuPct: _num(decoded['Cpu']),
      memUsedGb: used,
      memTotalGb: totalKb == null ? null : totalKb / 1048576,
      cpuTempC: _num(decoded['CpuTempC']),
    );
  }

  /// `nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu
  /// --format=csv,noheader,nounits`. One line per card; we read the first.
  static SystemStats nvidia(String csv) {
    final line = const LineSplitter()
        .convert(csv)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .firstOrNull;
    if (line == null) return const SystemStats();
    final cells = line.split(',').map((c) => c.trim()).toList();
    if (cells.length < 3) return const SystemStats();
    return SystemStats(
      gpuName: cells[0].isEmpty ? null : cells[0],
      gpuPct: double.tryParse(cells[1]),
      gpuTempC: double.tryParse(cells[2]),
    );
  }

  /// Two samples of /proc/stat, taken about a second apart. The busy share
  /// between them is the CPU load; one sample on its own is uptime, not load.
  static double? linuxCpuPct(String first, String second) {
    final a = _cpuTotals(first);
    final b = _cpuTotals(second);
    if (a == null || b == null) return null;
    final totalDelta = b.$1 - a.$1;
    final idleDelta = b.$2 - a.$2;
    if (totalDelta <= 0) return null;
    return ((totalDelta - idleDelta) / totalDelta * 100).clamp(0, 100);
  }

  /// /proc/meminfo. MemAvailable is what is actually free to use.
  static SystemStats linuxMemory(String meminfo) {
    final values = <String, double>{};
    for (final line in const LineSplitter().convert(meminfo)) {
      final parts = line.split(':');
      if (parts.length < 2) continue;
      final kb = double.tryParse(parts[1].trim().split(RegExp(r'\s+')).first);
      if (kb != null) values[parts[0].trim()] = kb;
    }
    final total = values['MemTotal'];
    final available = values['MemAvailable'] ?? values['MemFree'];
    if (total == null) return const SystemStats();
    return SystemStats(
      memTotalGb: total / 1048576,
      memUsedGb: available == null ? null : (total - available) / 1048576,
    );
  }

  /// Millidegrees from a thermal zone, for example /sys/class/thermal.
  static double? linuxTempC(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) return null;
    return value > 1000 ? value / 1000 : value;
  }

  /// (total, idle) jiffies from the first `cpu ` line.
  static (double, double)? _cpuTotals(String procStat) {
    final line = const LineSplitter()
        .convert(procStat)
        .where((l) => l.startsWith('cpu '))
        .firstOrNull;
    if (line == null) return null;
    final fields = line
        .substring(4)
        .trim()
        .split(RegExp(r'\s+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (fields.length < 4) return null;
    final total = fields.reduce((a, b) => a + b);
    final idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
    return (total, idle);
  }

  static Map<String, dynamic>? _firstObject(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map<String, dynamic>) return first;
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  static double? _num(Object? value) => switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
}
