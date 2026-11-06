import 'dart:io';

import 'package:chappy_player/core/miniapp_game_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('game server TLS URL policy', () {
    test('accepts explicit HTTPS and WSS public DNS names only', () {
      final https = GameNetworkPolicy.validate(
        'https://game.example.org:8443/api/room', websocket: false);
      final wss = GameNetworkPolicy.validate(
        'wss://game.example.org/chat?room=test', websocket: true);
      expect(https.port, 8443);
      expect(GameNetworkPolicy.origin(https), 'https://game.example.org:8443');
      expect(GameNetworkPolicy.origin(wss), 'wss://game.example.org:443');
    });
    test('rejects dangerous or ambiguous destinations', () {
      for (final value in <String>[
        'http://game.example.org/',
        'https://127.0.0.1/',
        'https://192.168.1.12/',
        'https://localhost/',
        'https://server.local/',
        'https://game.internal/',
        'https://host.invalid/',
        'https://user:password@game.example.org/',
        'https://game.example.org:8080/',
        'https://game.example.org/#fragment',
        'https://game.example.org./',
      ]) {
        expect(
          () => GameNetworkPolicy.validate(value, websocket: false),
          throwsFormatException,
          reason: value,
        );
      }
      for (final value in <String>[
        'ws://game.example.org/',
        'wss://192.168.0.1/',
        'wss://game.example.org:8888/',
        'wss://game.example.org/#fragment',
      ]) {
        expect(
          () => GameNetworkPolicy.validate(value, websocket: true),
          throwsFormatException, reason: value,
        );
      }
    });
  });

  group('IP restrictions and DNS pin selection', () {
    test('rejects private, reserved and loopback addresses', () {
      for (final ip in <String>[
        '127.0.0.1', '10.0.0.1', '172.16.0.1',
        '192.168.0.1', '169.254.2.3', '100.64.0.1',
        '192.0.2.1', '198.51.100.2', '203.0.113.1',
        '224.0.0.1', '::1', 'fe80::1', 'fd00::123',
      ]) {
        expect(GameNetworkPolicy.isPublicAddress(InternetAddress(ip)),
            false, reason: ip);
      }
    });
    test('allows global unicast only', () {
      expect(GameNetworkPolicy.isPublicAddress(
          InternetAddress('8.8.8.8')), true);
      expect(GameNetworkPolicy.isPublicAddress(
          InternetAddress('2001:4860:4860::8888')), true);
    });
    test('rejects mixed public/private DNS resolutions', () async {
      expect(
        GameNetworkPolicy.resolvePublic('game.example.org',
          lookup: (host) async => [
            InternetAddress('8.8.8.8'), InternetAddress('127.0.0.1'),
          ]),
        throwsFormatException,
      );
      final selected = await GameNetworkPolicy.resolvePublic(
          'game.example.org',
          lookup: (host) async => [
            InternetAddress('2001:4860:4860::8888'),
            InternetAddress('8.8.8.8'),
          ]);
      expect(selected.address, '8.8.8.8');
    });
  });

  test('closed session never reports connected or sends data', () {
    final session = MiniAppGameNetwork();
    expect(session.poll()['connected'], false);
    expect(session.poll()['messages'], isEmpty);
    expect(session.send('hello'), false);
    session.pause();
    expect(session.poll()['connected'], false);
    session.resume();
    expect(session.poll()['connected'], false);
    session.close();
  });
}
