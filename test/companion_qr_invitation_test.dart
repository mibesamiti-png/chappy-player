import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fp = List<String>.filled(64, 'a').join();
  final token = List<String>.filled(32, 'b').join();
  final knownNow = DateTime.fromMillisecondsSinceEpoch(
    1799999700000, isUtc: true,
  );
  final encoded =
      'chappy-pair://v2?ip=192.168.1.7&port=49152'
      '&fp=$fp&inv=$token&exp=1800000000';

  test('PC and Android agree on strict QR payload and expiry', () {
    final invite = CompanionQrInvitation.parse(encoded, now: knownNow);
    expect(invite.ip, '192.168.1.7');
    expect(invite.port, 49152);
    expect(invite.fingerprint, fp);
    expect(invite.invitation, token);
    expect(invite.expiresUnix, 1800000000);
    expect(
      CompanionPairingClient.isPrivateIpv4(invite.ip),
      isTrue,
    );
  });

  test('QR-v3 binds short-lived TLS pin to explicit PC identity fingerprint', () {
    final pc = List<String>.filled(64, 'c').join();
    final modern = '${encoded.replaceFirst('://v2', '://v3')}&pc=$pc';
    final parsed = CompanionQrInvitation.parse(modern, now: knownNow);
    expect(parsed.pcIdentityFingerprint, pc);
    expect(parsed.fingerprint, fp);
    expect(parsed.invitation, token);
    expect(CompanionQrInvitation.parse(encoded, now: knownNow)
        .pcIdentityFingerprint, isNull);
    for (final malformed in <String>[
      modern.replaceFirst('&pc=$pc', ''),
      modern.replaceFirst('&pc=$pc', '&pc=ABC'),
      '$modern&pc=$pc',
      '$encoded&pc=$pc',
      modern.replaceFirst('pc=$pc', 'pc=${pc.toUpperCase()}'),
      modern.replaceFirst('://v3', '://v4'),
    ]) {
      expect(() => CompanionQrInvitation.parse(malformed, now: knownNow),
          throwsFormatException);
    }
  });

  test('expired and too-far invitations are rejected', () {
    expect(
      () => CompanionQrInvitation.parse(
        encoded,
        now: DateTime.fromMillisecondsSinceEpoch(
          1800000000000, isUtc: true,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => CompanionQrInvitation.parse(
        encoded,
        now: DateTime.fromMillisecondsSinceEpoch(
          1799999000000, isUtc: true,
        ),
      ),
      throwsFormatException,
    );
  });

  test('wrong hosts, extra keys, public endpoints and duplicate keys fail', () {
    for (final altered in <String>[
      encoded.replaceFirst('chappy-pair://v2', 'https://v2'),
      encoded.replaceFirst('192.168.1.7', '8.8.8.8'),
      encoded.replaceFirst('port=49152', 'port=0'),
      encoded.replaceFirst('port=49152', 'port=49152&port=49153'),
      '$encoded&redirect=http://example.com',
      '$encoded#fragment',
      encoded.replaceFirst('inv=$token', 'inv=not-a-token'),
      encoded.replaceFirst('&fp=$fp', '&fp=abc'),
      encoded.replaceFirst('&exp=1800000000', '&exp=9999999999'),
    ]) {
      expect(
        () => CompanionQrInvitation.parse(altered, now: knownNow),
        throwsFormatException,
        reason: altered.substring(0, 28),
      );
    }
  });

  test('manual pairing is unchanged; invalid QR secret never connects', () async {
    final client = CompanionPairingClient();
    await expectLater(
      client.confirm(
        ip: '192.168.1.7',
        port: 49152,
        fingerprint: fp,
        nonce: '0123456789abcdef0123456789abcdef',
        invitation: 'abc',
      ),
      throwsFormatException,
    );
    client.cancel();
  });
}
