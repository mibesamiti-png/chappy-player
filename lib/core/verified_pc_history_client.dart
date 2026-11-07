import 'package:flutter/services.dart';

/// Public-fingerprint notes only, never reusable authorization or credentials.
/// Native AndroidKeyStore encrypts the local file; trusted Flutter host only.
class VerifiedPcHistoryClient {
  final MethodChannel channel;

  const VerifiedPcHistoryClient({
    this.channel = const MethodChannel('dev.chappy.player/network_lab'),
  });

  Future<List<VerifiedPcRecord>> list() => _load('verifiedPcList');

  /// Call only after *successful QR-v3 mutual proof* and separate user consent.
  Future<List<VerifiedPcRecord>> remember(String fingerprint) =>
      _load('verifiedPcRemember', fingerprint);

  /// Local removal only; cannot revoke a credential on a remote PC.
  Future<List<VerifiedPcRecord>> forget(String fingerprint) =>
      _load('verifiedPcForget', fingerprint);

  /// Erase encrypted local history AND its AES key, retaining the P-256 identity.
  /// The trusted UI must confirm this separate destructive action explicitly.
  Future<List<VerifiedPcRecord>> clear() => _load('verifiedPcClear');

  Future<List<VerifiedPcRecord>> _load(
    String method, [
    String? fingerprint,
  ]) async {
    if (fingerprint != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('PCの公開鍵指紋が不正です');
    }
    final raw = await channel.invokeMethod<List<dynamic>>(
      method,
      fingerprint == null
          ? null
          : <String, String>{'fingerprint': fingerprint},
    );
    if (raw == null || raw.length > 24) {
      throw const FormatException('保存されたPC確認履歴が不正です');
    }
    final unique = <String>{};
    final entries = <VerifiedPcRecord>[];
    for (final value in raw) {
      if (value is! Map) {
        throw const FormatException('PC確認履歴の形式が不正です');
      }
      final entry = VerifiedPcRecord.fromWire(value);
      if (!unique.add(entry.fingerprint)) {
        throw const FormatException('PC確認履歴の重複があります');
      }
      entries.add(entry);
    }
    return List<VerifiedPcRecord>.unmodifiable(entries);
  }
}

class VerifiedPcRecord {
  final String fingerprint;
  final int addedUnix;

  const VerifiedPcRecord({
    required this.fingerprint,
    required this.addedUnix,
  });

  factory VerifiedPcRecord.fromWire(Map<dynamic, dynamic> value) {
    final fingerprint = value['fingerprint'];
    final added = value['added'];
    if (value.length != 2 ||
        fingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        added is! int ||
        added <= 0) {
      throw const FormatException('PC確認履歴の検証に失敗しました');
    }
    return VerifiedPcRecord(
      fingerprint: fingerprint,
      addedUnix: added,
    );
  }
}
