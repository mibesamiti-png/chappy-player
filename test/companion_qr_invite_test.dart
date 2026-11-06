import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/companion_qr_invite.dart';
import 'package:chappy_player/screens/network_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pin = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const ticket = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const uri = 'chappy-pair://invite?v=1&ip=192.168.1.77&port=45678'
      '&fp=$pin&exp=1794050600&ticket=$ticket';

  test('Dart parses the canonical Windows invitation with strict fields', () {
    final invite = CompanionQrInvite.parse(uri, nowSeconds: 1794050000);
    expect(invite.ip, '192.168.1.77');
    expect(invite.port, 45678);
    expect(invite.fingerprint, pin);
    expect(invite.expiresAt, 1794050600);
    expect(invite.ticket, ticket);
    expect(invite.isExpired(nowSeconds: 1794050600), isTrue);
    expect(invite.isExpired(nowSeconds: 1794050000), isFalse);
  });

  test('Dart refuses tampered, expired, public, duplicate QR data', () {
    final tampered = <String>[
      uri.replaceFirst('192.168.1.77', '8.8.8.8'),
      uri.replaceFirst('chappy-pair:', 'https:'),
      uri.replaceFirst('v=1', 'v=2'),
      uri.replaceFirst('exp=1794050600', 'exp=1794053000'),
      uri.replaceFirst('exp=1794050600', 'exp=1794049999'),
      uri.replaceFirst('&fp=$pin', '&fp=bad'),
      '$uri&admin=1',
      '$uri&ticket=$ticket',
      uri.replaceFirst('ticket=$ticket', 'ticket=invalid'),
      'not-a-link',
    ];
    for (final bad in tampered) {
      expect(
        () => CompanionQrInvite.parse(bad, nowSeconds: 1794050000),
        throwsFormatException,
        reason: bad,
      );
    }
    expect(
      () => CompanionQrInvite.parse(uri, nowSeconds: 1794050600),
      throwsFormatException,
    );
  });

  test('expired/invalid QR ticket cannot open any socket', () async {
    final client = CompanionPairingClient();
    await expectLater(
      client.confirm(
        ip: '192.168.1.77',
        port: 45678,
        fingerprint: pin,
        nonce: '0123456789abcdef0123456789abcdef',
        invitationTicket: 'bad',
        expiresAt: 1794050600,
      ),
      throwsFormatException,
    );
    await expectLater(
      client.confirm(
        ip: '192.168.1.77',
        port: 45678,
        fingerprint: pin,
        nonce: '0123456789abcdef0123456789abcdef',
        invitationTicket: ticket,
        expiresAt: 1794050600,
      ),
      throwsFormatException,
    );
  });

  testWidgets('Network Lab exposes QR scanning only via manual action',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NetworkLabPage()),
    );
    expect(find.byKey(const Key('netlab_scan_pc_qr')), findsOneWidget);
    expect(find.text('PC画面のQRを読み取って接続確認'), findsOneWidget);
    // Camera page is not created or opened merely by visiting Network Lab.
    expect(find.text('PCのQRコードを読み取る'), findsNothing);
  });
}
