import 'package:flutter/services.dart';

/// A host-only public key lifecycle for FUTURE PC pairing.
///
/// This is not device registration, not a network credential, and never
/// returns a private key or a signing API to Flutter or .chappy JavaScript.
class PcIdentityClient {
  final MethodChannel _channel;
  const PcIdentityClient({
    MethodChannel channel =
        const MethodChannel('dev.chappy.player/network_lab'),
  }) : _channel = channel;

  Future<PcIdentityStatus> status() async => PcIdentityStatus.fromWire(
    await _channel.invokeMapMethod<String, dynamic>('pcIdentityStatus'),
  );

  Future<PcIdentityStatus> create() async => PcIdentityStatus.fromWire(
    await _channel.invokeMapMethod<String, dynamic>('pcIdentityCreate'),
  );

  /// Requires the exact public fingerprint that the user confirmed in the UI.
  /// The native KeyStore owner must compare this again before any deletion.
  Future<bool> revoke(String expectedFingerprint) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedFingerprint)) {
      throw const FormatException('削除対象の端末公開鍵指紋が不正です');
    }
    return await _channel.invokeMethod<bool>(
      'pcIdentityRevoke',
      <String, String>{'fingerprint': expectedFingerprint},
    ) == true;
  }
}

class PcIdentityStatus {
  final bool created;
  final String? fingerprint;
  final String algorithm;

  const PcIdentityStatus({
    required this.created,
    required this.algorithm,
    required this.fingerprint,
  });

  factory PcIdentityStatus.fromWire(Map<String, dynamic>? data) {
    if (data == null ||
        data['algorithm'] != 'P-256' ||
        data['created'] is! bool) {
      throw const FormatException('Android端末キーの状態が不正です');
    }
    final created = data['created'] as bool;
    final fp = data['fingerprint'];
    if (created) {
      if (fp is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fp)) {
        throw const FormatException('端末の公開鍵指紋が不正です');
      }
    } else if (fp != null) {
      throw const FormatException('未作成の端末に公開鍵指紋があります');
    }
    return PcIdentityStatus(
      created: created,
      algorithm: 'P-256',
      fingerprint: fp as String?,
    );
  }
}
