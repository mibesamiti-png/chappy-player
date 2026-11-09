import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/pc_traffic_once.dart';
import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Python/Dart traffic scope vectors remain compatible', () {
    final data = jsonDecode(
      File('docs/netlab-04b-traffic-vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final item in data['cases'] as List) {
      final row = item as Map<String, dynamic>;
      expect(pcTrafficScopedNonce(row['nonce'] as String,
          row['seconds'] as int), row['sha256']);
    }
    expect(() => pcTrafficScopedNonce('c' * 64, 4), throwsFormatException);
    expect(() => pcTrafficScopedNonce('c' * 64, 31), throwsFormatException);
    expect(() => pcTrafficScopedNonce('z' * 64, 10), throwsFormatException);
    expect(pcTrafficScopedNonce('c' * 64, 5),
        isNot(pcTrafficScopedNonce('c' * 64, 10)));
  });

  test('QR-v3 traffic scope is exclusive, no legacy or silent privilege', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1799999700000, isUtc: true);
    const base = 'chappy-pair://v3?ip=192.168.1.7&port=49152'
        '&fp=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        '&inv=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&exp=1800000000'
        '&pc=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final allowed = CompanionQrInvitation.parse('$base&traffic=1', now: now);
    expect(allowed.trafficOnce, isTrue);
    expect(allowed.statusOnce, isFalse);
    expect(allowed.mediaOnce, isFalse);
    for (final bad in [
      '$base&traffic=2',
      '$base&traffic=1&traffic=1',
      '$base&traffic=1&status=1',
      '$base&traffic=1&file=1',
      '$base&traffic=1&media=1',
      '${base.replaceFirst('://v3', '://v2')}&traffic=1',
    ]) {
      expect(() => CompanionQrInvitation.parse(bad, now: now),
          throwsFormatException);
    }
  });
}
