import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/pc_media_once.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Python/Dart fixtures agree on every exact command scoped nonce', () {
    final data = jsonDecode(
      File('docs/pc-link-r6b-media-vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(data['protocol'], PcMediaOnce.protocol);
    expect(data['scope'], 'pc.media.control');
    expect(data['domain'], 'CHAPPY-PC-MEDIA-CONTROL-V1');
    final entries = data['vectors'] as List<dynamic>;
    expect(entries.length, 2);
    for (final item in entries) {
      final entry = item as Map<String, dynamic>;
      final nonce = entry['raw_nonce_hex'] as String;
      final commands = entry['commands'] as Map<String, dynamic>;
      expect(commands.keys.toSet(), PcMediaOnce.commands.toSet());
      for (final command in PcMediaOnce.commands) {
        final scoped = pcMediaScopedNonce(nonce, command);
        expect(scoped, commands[command]);
        expect(scoped, isNot(nonce));
      }
      expect(commands.values.toSet().length, PcMediaOnce.commands.length);
    }
  });

  test('Invalid or cross-scope key names are rejected by host model', () {
    const nonce = 'ffffffffffffffffffffffffffffffff'
        'ffffffffffffffffffffffffffffffff';
    for (final bad in ['media', 'STATUS', 'volume_up;cmd', 'volume_up\n', '']) {
      expect(() => pcMediaScopedNonce(nonce, bad), throwsFormatException);
    }
    expect(() => pcMediaScopedNonce('FF', 'play_pause'),
        throwsFormatException);
  });
}
