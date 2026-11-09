import 'dart:io';

import 'package:chappy_player/core/companion_pairing_client.dart';

/// Strict, ephemeral QR bootstrap data copied from the physical PC display.
///
/// Parsing grants no trust or PC access. TLS must still pin the full SHA-256
/// fingerprint, and PC must independently approve the one-shot confirmation.
class CompanionQrInvitation {
  final String ip;
  final int port;
  final String fingerprint;
  final String invitation;
  final int expiresUnix;
  final String? pcIdentityFingerprint;
  final bool statusOnce;

  const CompanionQrInvitation({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.invitation,
    required this.expiresUnix,
    this.pcIdentityFingerprint,
    this.statusOnce = false,
  });

  static CompanionQrInvitation parse(
    String raw, {
    DateTime? now,
  }) {
    if (raw.length > 384 || raw.length < 125 ||
        !RegExp(r'^[\x21-\x7e]+$').hasMatch(raw)) {
      throw const FormatException('QRデータの長さまたは文字が不正です');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'chappy-pair' ||
        (uri.host != 'v2' && uri.host != 'v3') ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw const FormatException('Chappy PC用のQRではありません');
    }
    final isV3 = uri.host == 'v3';
    final expected = <String>{
      'ip', 'port', 'fp', 'inv', 'exp', if (isV3) 'pc',
    };
    final parameters = uri.queryParametersAll;
    final statusPresent = isV3 && parameters.containsKey('status');
    if (statusPresent) expected.add('status');
    if (parameters.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(parameters.keys.toSet()).isNotEmpty ||
        parameters.values.any((items) => items.length != 1) ||
        (statusPresent && parameters['status']!.single != '1')) {
      throw const FormatException('QR項目が不足・重複しています');
    }
    final ip = parameters['ip']!.single;
    final address = InternetAddress.tryParse(ip);
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.address != ip ||
        !CompanionPairingClient.isPrivateIpv4(ip)) {
      throw const FormatException('QRのIPがローカルIPv4ではありません');
    }
    final portText = parameters['port']!.single;
    final expiryText = parameters['exp']!.single;
    final pin = parameters['fp']!.single;
    final token = parameters['inv']!.single;
    final pc = isV3 ? parameters['pc']!.single : null;
    if (pc != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(pc)) {
      throw const FormatException('PCの端末公開鍵指紋が不正です');
    }
    if (!RegExp(r'^[0-9]{1,5}$').hasMatch(portText) ||
        !RegExp(r'^[0-9]{10}$').hasMatch(expiryText) ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      throw const FormatException('QRのポート・有効期限・招待IDが不正です');
    }
    final port = int.parse(portText);
    final expiry = int.parse(expiryText);
    CompanionPairingClient.validateTarget(ip, port, pin);
    if (CompanionPairingClient.normalizeFingerprint(pin) != pin) {
      throw const FormatException('QRの証明書指紋の書式が不正です');
    }
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (expiry <= current || expiry - current > 600) {
      throw const FormatException('QRの有効期限が切れたか遠すぎます');
    }
    return CompanionQrInvitation(
      ip: ip, port: port, fingerprint: pin,
      invitation: token, expiresUnix: expiry,
      pcIdentityFingerprint: pc,
      statusOnce: statusPresent,
    );
  }
}
