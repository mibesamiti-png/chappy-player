import 'dart:math';

import 'package:chappy_player/core/pc_identity_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Trusted Flutter-host adapter. No method in this class is bridged to
/// .chappy HTML/JS. A QR-v3 pairing action requires foreground consent.
class CompanionIdentityClient {
  final MethodChannel channel;
  final PcIdentityClient identity;

  const CompanionIdentityClient({
    this.channel = const MethodChannel('dev.chappy.player/network_lab'),
    this.identity = const PcIdentityClient(),
  });

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  static String newNonce() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String confirmationCode(String phoneNonce) {
    if (!_hex64.hasMatch(phoneNonce)) {
      throw const FormatException('スマホの認証用乱数が不正です');
    }
    final bytes = <int>[
      for (var i = 0; i < phoneNonce.length; i += 2)
        int.parse(phoneNonce.substring(i, i + 2), radix: 16),
    ];
    return sha256.convert(bytes).toString().substring(0, 6).toUpperCase();
  }

  static Map<String, String> parseProof(Map<dynamic, dynamic>? raw) {
    if (raw == null || raw.length != 3 ||
        raw['algorithm'] != 'P-256-SHA256' ||
        raw['spki'] is! String || raw['signature'] is! String) {
      throw const FormatException('端末署名の形式が不正です');
    }
    final spki = raw['spki'] as String;
    final sig = raw['signature'] as String;
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
    if (spki.length > 344 || sig.length > 344 ||
        !base64Pattern.hasMatch(spki) || !base64Pattern.hasMatch(sig)) {
      throw const FormatException('端末署名の長さまたはエンコードが不正です');
    }
    return <String, String>{
      'algorithm': 'P-256-SHA256', 'spki': spki, 'signature': sig,
    };
  }

  Future<PcIdentityStatus> status() => identity.status();

  Future<bool> verifyPcProof({
    required Map<String, String> proof,
    required String pcFingerprint,
    required String invitation,
    required String tlsFingerprint,
    required String phoneFingerprint,
    required String phoneNonce,
    required int expiresUnix,
  }) async {
    final result = await channel.invokeMethod<bool>(
      'pcIdentityVerifyProof',
      <String, Object>{
        'proof': proof,
        'expectedFp': pcFingerprint,
        'role': 'pc',
        'invitation': invitation,
        'tlsFp': tlsFingerprint,
        'peerFp': phoneFingerprint,
        'nonce': phoneNonce,
        'expires': expiresUnix,
      },
    );
    return result == true;
  }

  Future<Map<String, String>> signPhoneProof({
    required String invitation,
    required String tlsFingerprint,
    required String pcFingerprint,
    required String pcNonce,
    required int expiresUnix,
  }) async {
    final response = await channel.invokeMapMethod<String, dynamic>(
      'pcIdentitySignProof',
      <String, Object>{
        'invitation': invitation,
        'tlsFp': tlsFingerprint,
        'peerFp': pcFingerprint,
        'nonce': pcNonce,
        'expires': expiresUnix,
      },
    );
    return parseProof(response);
  }
}
