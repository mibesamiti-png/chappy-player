import 'package:chappy_player/core/companion_identity_client.dart';
import 'package:chappy_player/core/pc_identity_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  final fingerprint = List<String>.filled(64, 'a').join();
  final invitation = List<String>.filled(32, 'b').join();
  final nonce = List<String>.filled(64, 'c').join();
  final publicProof = <String, String>{
    'algorithm': 'P-256-SHA256',
    'spki': 'QUJDRA==',
    'signature': 'RUZHSA==',
  };

  test('32-byte identity nonce and PC comparison code match SHA-256 vector', () {
    final first = CompanionIdentityClient.newNonce();
    final second = CompanionIdentityClient.newNonce();
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first), isTrue);
    expect(first, isNot(second));
    expect(CompanionIdentityClient.confirmationCode(nonce), '229DCA');
    expect(
      () => CompanionIdentityClient.confirmationCode('a' * 32),
      throwsFormatException,
    );
  });

  test('proof parsing requires bounded public fields with no secret values', () {
    expect(CompanionIdentityClient.parseProof(publicProof), publicProof);
    for (final broken in <Map<dynamic, dynamic>>[
      {'algorithm': 'P-384-SHA384', 'spki': 'QUJD', 'signature': 'RUZH'},
      {'algorithm': 'P-256-SHA256', 'spki': '', 'signature': 'RUZH'},
      {...publicProof, 'private': 'SHOULD NEVER BE EXPORTED'},
      {...publicProof, 'signature': '?' * 600},
    ]) {
      expect(
        () => CompanionIdentityClient.parseProof(broken),
        throwsFormatException,
      );
    }
  });

  test('host-only proof calls never create a key or touch mini-app JS', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'pcIdentityStatus') {
        return <String, Object>{
          'created': true, 'algorithm': 'P-256', 'fingerprint': fingerprint,
        };
      }
      if (call.method == 'pcIdentityVerifyProof') {
        expect(call.arguments['role'], 'pc');
        expect(call.arguments['expectedFp'], fingerprint);
        expect(call.arguments['peerFp'], fingerprint);
        expect(call.arguments['nonce'], nonce);
        expect(call.arguments['invitation'], invitation);
        return true;
      }
      if (call.method == 'pcIdentitySignProof') {
        expect(call.arguments['nonce'], nonce);
        return publicProof;
      }
      throw UnimplementedError(call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const client = CompanionIdentityClient(
      channel: channel,
      identity: PcIdentityClient(channel: channel),
    );
    final current = await client.status();
    expect(current.created, isTrue);
    expect(await client.verifyPcProof(
      proof: publicProof, pcFingerprint: fingerprint,
      invitation: invitation, tlsFingerprint: fingerprint,
      phoneFingerprint: fingerprint, phoneNonce: nonce,
      expiresUnix: 2000000000,
    ), isTrue);
    expect(await client.signPhoneProof(
      invitation: invitation, tlsFingerprint: fingerprint,
      pcFingerprint: fingerprint, pcNonce: nonce, expiresUnix: 2000000000,
    ), publicProof);
    expect(methods, <String>[
      'pcIdentityStatus', 'pcIdentityVerifyProof', 'pcIdentitySignProof',
    ]);
  });
}
