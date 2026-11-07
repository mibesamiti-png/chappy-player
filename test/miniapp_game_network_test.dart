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
    test('normalizes only implicit WSS port to 443 before HTTPS upgrade', () {
      final implicit = GameNetworkPolicy.validate(
        'wss://ws.postman-echo.com/raw', websocket: true);
      expect(implicit.hasPort, false);
      // Dart Uri only recognizes http/https defaults; wss.port == 0.
      expect(implicit.port, 0);
      final explicit = GameNetworkPolicy.websocketConnectUri(implicit);
      expect(explicit.scheme, 'wss');
      expect(explicit.hasPort, true);
      expect(explicit.port, 443);
      expect(explicit.host, implicit.host);
      expect(explicit.path, '/raw');
      expect(GameNetworkPolicy.origin(implicit),
          'wss://ws.postman-echo.com:443');

      // This mirrors the conversion in Dart SDK WebSocket.connect:
      // wss -> https, copying [uri.port]. Port must stay 443, never 0.
      final httpsUpgrade = Uri(
        scheme: 'https', host: explicit.host, port: explicit.port,
        path: explicit.path, query: explicit.query,
      );
      expect(httpsUpgrade.port, 443);
      expect(httpsUpgrade.scheme, 'https');

      final custom = GameNetworkPolicy.validate(
        'wss://game.example.org:8443/room?x=1', websocket: true);
      final unchanged = GameNetworkPolicy.websocketConnectUri(custom);
      expect(unchanged.toString(), custom.toString());
      expect(unchanged.port, 8443);
      expect(() => GameNetworkPolicy.websocketConnectUri(
          Uri.parse('https://game.example.org/room')), throwsFormatException);
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
        '192.0.0.77', '192.88.99.1',
        '224.0.0.1', '::1', 'fe80::1', 'fd00::123',
        '2001:db8::1', '2001:2::1', '2002:c000:0201::1',
        '3fff::1', '3f00::1', '2d00::1', '2000::1',
        '2640:ffff::1', '2420:ffff::1',
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
      for (final ip in <String>[
        '2402:1234::1', '2606:4700::1111',
        '2800::1', '2a03::1', '2c00::1', '2003::1',
      ]) {
        expect(GameNetworkPolicy.isPublicAddress(InternetAddress(ip)),
            true, reason: ip);
      }
    });
    test('rejects mixed public/private DNS resolutions', () async {
      expect(
        GameNetworkPolicy.resolvePublic('game.example.org',
          lookup: (host) async => [
            InternetAddress('8.8.8.8'), InternetAddress('127.0.0.1'),
          ]),
        throwsFormatException,
      );
      expect(
        GameNetworkPolicy.resolvePublic('game.example.org',
          lookup: (host) async => [
            InternetAddress('2001:db8::1'), InternetAddress('8.8.8.8'),
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
