import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/native_tools/stats_parsers.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('windows', () {
    test('reads cpu and memory out of the PowerShell object', () {
      final stats = StatsParsers.windows(_fixture('win_stats.json'));

      expect(stats.cpuPct, 17);
      expect(stats.memTotalGb, closeTo(31.86, 0.01));
      expect(stats.memUsedGb, closeTo(12.93, 0.01));
    });

    test('survives an empty or broken answer', () {
      expect(StatsParsers.windows('').cpuPct, isNull);
      expect(StatsParsers.windows('not json').memTotalGb, isNull);
    });

    test('takes the first object when PowerShell emits an array', () {
      final stats = StatsParsers.windows('[{"Cpu":"42"},{"Cpu":1}]');

      expect(stats.cpuPct, 42);
    });
  });

  group('nvidia-smi', () {
    test('reads name, load and temperature', () {
      final stats = StatsParsers.nvidia(_fixture('nvidia_smi.csv'));

      expect(stats.gpuName, 'NVIDIA GeForce RTX 4070');
      expect(stats.gpuPct, 34);
      expect(stats.gpuTempC, 51);
    });

    test('no card means no readings, not a crash', () {
      expect(StatsParsers.nvidia('').gpuName, isNull);
      expect(StatsParsers.nvidia('\n \n').gpuPct, isNull);
    });
  });

  group('linux', () {
    test('cpu load is the busy share between two /proc/stat samples', () {
      final pct = StatsParsers.linuxCpuPct(
        _fixture('proc_stat_a.txt'),
        _fixture('proc_stat_b.txt'),
      );

      // total delta 500, idle plus iowait delta 460, so 40 of 500.
      expect(pct, closeTo(8, 0.01));
    });

    test('one sample on its own gives nothing', () {
      final same = _fixture('proc_stat_a.txt');

      expect(StatsParsers.linuxCpuPct(same, same), isNull);
      expect(StatsParsers.linuxCpuPct('', ''), isNull);
    });

    test('memory uses MemAvailable, not MemFree', () {
      final stats = StatsParsers.linuxMemory(_fixture('proc_meminfo.txt'));

      expect(stats.memTotalGb, closeTo(31.18, 0.01));
      expect(stats.memUsedGb, closeTo(12.63, 0.01));
    });

    test('temperature comes in millidegrees, sometimes degrees', () {
      expect(StatsParsers.linuxTempC('52000\n'), 52);
      expect(StatsParsers.linuxTempC('52'), 52);
      expect(StatsParsers.linuxTempC(''), isNull);
    });
  });

  test('spoken line skips whatever the OS did not give us', () {
    final stats = StatsParsers.windows(_fixture('win_stats.json'));

    expect(stats.spoken, 'CPU 17 percent, RAM 12.9 of 31.9 gigabytes');
    expect(StatsParsers.windows('').spoken, 'No readings available');
  });
}
