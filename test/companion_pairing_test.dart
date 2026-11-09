import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/screens/companion_pairing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  const service = LanDiscoveredService(
    id: '_workstation._tcp.|Chappy PC test',
    name: 'Chappy PC test',
    type: '_workstation._tcp.',
    address: '192.168.1.7',
    port: 49152,
    resolved: true,
  );

  test('nonce confirmation vector matches Windows SHA-256 implementation', () {
    expect(
      CompanionPairingClient.confirmationCode(
        '0123456789abcdef0123456789abcdef',
      ),
      '223E0A',
    );
    final nonceA = CompanionPairingClient.newNonce();
    final nonceB = CompanionPairingClient.newNonce();
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(nonceA), isTrue);
    expect(nonceA, isNot(nonceB));
    expect(
      () => CompanionPairingClient.confirmationCode('invalid'),
      throwsFormatException,
    );
  });

  test('only private IPv4 and full fingerprint are accepted', () {
    for (final ip in ['10.1.2.3', '172.16.5.2', '192.168.1.7']) {
      expect(CompanionPairingClient.isPrivateIpv4(ip), isTrue);
    }
    for (final ip in [
      '8.8.8.8', '127.0.0.1', '169.254.0.7',
      '100.64.0.1', '2001:db8::1', 'not-an-ip',
    ]) {
      expect(CompanionPairingClient.isPrivateIpv4(ip), isFalse);
    }
    expect(
      CompanionPairingClient.normalizeFingerprint(
        List<String>.filled(32, 'AB').join(':'),
      ),
      List<String>.filled(32, 'ab').join(),
    );
    for (final badPin in ['', 'abc123', List<String>.filled(64, 'Z').join()]) {
      expect(
        () => CompanionPairingClient.validateTarget(
          '192.168.1.7', 49152, badPin,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => CompanionPairingClient.validateTarget(
        '8.8.8.8', 49152, List<String>.filled(64, 'a').join(),
      ),
      throwsFormatException,
    );
    expect(
      () => CompanionPairingClient.validateTarget(
        '192.168.1.7', 0, List<String>.filled(64, 'a').join(),
      ),
      throwsFormatException,
    );
  });

  testWidgets('pairing screen requires fingerprint before contacting Android',
      (tester) async {
    var channelRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelRequests++;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(const MaterialApp(
      home: CompanionPairingPage(
        service: service,
        discoveryClient: LanDiscoveryClient(channel: channel),
      ),
    ));
    expect(find.text('Chappy PC test'), findsOneWidget);
    expect(find.byKey(const Key('pair_fingerprint')), findsOneWidget);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('pair_confirm')));
    await tester.tap(find.byKey(const Key('pair_confirm')));
    await tester.pump();
    expect(channelRequests, 0);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
  });

  test('host eligibility channel explicitly declines without Android approval',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const client = LanDiscoveryClient(channel: channel);
    expect(await client.pairingAllowed(), isFalse);
  });
  testWidgets('NETLAB-04B traffic control stays hidden until actual QR-v3 verification',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 180;
    await tester.pumpWidget(MaterialApp(
      home: CompanionPairingPage(
        service: service,
        discoveryClient: const LanDiscoveryClient(channel: channel),
        qrReader: (_) async => CompanionQrInvitation(
          ip: service.address, port: service.port,
          fingerprint: 'a' * 64, invitation: 'b' * 32,
          expiresUnix: expires, pcIdentityFingerprint: 'c' * 64,
          trafficOnce: true,
        ),
      ),
    ));
    expect(find.byKey(const Key('pair_traffic_once')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('pair_scan_qr')));
    await tester.tap(find.byKey(const Key('pair_scan_qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_traffic_once')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('pair_confirm')));
    await tester.tap(find.byKey(const Key('pair_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    expect(find.byKey(const Key('pair_traffic_once')), findsNothing);
  });

  test('NETLAB-04B fails closed when the native Wi-Fi/VPN guard denies', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'trafficPairingAllowed') return false;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const client = LanDiscoveryClient(channel: channel);
    expect(await client.pairingAllowed(), isTrue);
    expect(await client.trafficPairingAllowed(), isFalse);
  });

}
