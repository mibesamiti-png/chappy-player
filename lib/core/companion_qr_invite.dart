import 'package:chappy_player/core/companion_pairing_client.dart';

/// A short-lived PC-displayed QR invite. It is only a TLS endpoint locator,
/// NOT a stored paired identity or permission to operate the PC.
class CompanionQrInvite {
  final String ip;
  final int port;
  final String fingerprint;
  final int expiresAt;
  final String ticket;

  const CompanionQrInvite({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.expiresAt,
    required this.ticket,
  });

  static final _pattern = RegExp(
    r'^chappy-pair://invite\?v=1&ip=([0-9.]+)&port=([1-9][0-9]{0,4})'
    r'&fp=([0-9a-f]{64})&exp=([0-9]{10})&ticket=([0-9a-f]{32})$',
  );

  static CompanionQrInvite parse(
    String raw, {
    int? nowSeconds,
  }) {
    // Exact format: no arbitrary URL navigation, unknown fields or duplicates.
    if (raw.length > 256 || !raw.isAscii) {
      throw const FormatException('Chappy PCのQR形式ではありません');
    }
    final match = _pattern.firstMatch(raw);
    if (match == null) {
      throw const FormatException('Chappy PCのQR形式ではありません');
    }
    final ip = match.group(1)!;
    final port = int.parse(match.group(2)!);
    final fingerprint = match.group(3)!;
    final expiresAt = int.parse(match.group(4)!);
    final ticket = match.group(5)!;
    CompanionPairingClient.validateTarget(ip, port, fingerprint);
    final now = nowSeconds ??
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt <= now || expiresAt - now > 1800) {
      throw const FormatException('QRの有効期限が切れたか、時計がずれています');
    }
    return CompanionQrInvite(
      ip: ip,
      port: port,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
      ticket: ticket,
    );
  }

  bool isExpired({int? nowSeconds}) {
    final now = nowSeconds ??
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return now >= expiresAt;
  }
}

extension on String {
  bool get isAscii {
    for (final unit in codeUnits) {
      if (unit > 0x7f) return false;
    }
    return true;
  }
}
