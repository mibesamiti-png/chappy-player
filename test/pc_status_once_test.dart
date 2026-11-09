import 'package:chappy_player/core/pc_status_once.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nonce domain separation has the expected byte prefix', () {
    final raw = '1a' * 32;
    final scoped = pcStatusScopedNonce(raw);
    expect(scoped, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(scoped, isNot(raw));
    expect(() => pcStatusScopedNonce('abc'), throwsFormatException);
    expect(() => pcStatusScopedNonce('Z' * 64), throwsFormatException);
  });

  test('status allows unsupported null metrics; does not invent zero values',
      () {
    final snapshot = PcStatusOnceMetrics.parse({
      'available': false,
      'logical_cpus': null,
      'memory_total_bytes': null,
      'memory_available_bytes': null,
      'uptime_seconds': null,
    });
    expect(snapshot.available, isFalse);
    expect(snapshot.logicalCpus, isNull);
  });

  test('real typed snapshot excludes malformed or excessive data', () {
    final raw = <String, dynamic>{
      'available': true,
      'logical_cpus': 8,
      'memory_total_bytes': 16 * 1024 * 1024 * 1024,
      'memory_available_bytes': 4 * 1024 * 1024 * 1024,
      'uptime_seconds': 7200,
    };
    final parsed = PcStatusOnceMetrics.parse(raw);
    expect(parsed.logicalCpus, 8);
    for (final bad in <Map<String, dynamic>>[
      {...raw, 'hostname': 'private'},
      {...raw, 'available': 'yes'},
      {...raw, 'logical_cpus': true},
      {...raw, 'uptime_seconds': -1},
      {...raw, 'memory_available_bytes': 32 * 1024 * 1024 * 1024},
      {...raw}..remove('uptime_seconds'),
      {...raw, 'available': false},
    ]) {
      expect(() => PcStatusOnceMetrics.parse(bad), throwsFormatException);
    }
  });
}
