import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/companion_identity_client.dart';
import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:crypto/crypto.dart';

/// Explicit, one-shot QR-v3 proof exchange. No trusted peer is saved.
/// Neither success nor failure grants access to PC APIs.
class CompanionIdentityExchange {
  final CompanionIdentityClient identity;
  SecureSocket? _socket;
  bool _busy = false;
  bool _cancelled = false;

  CompanionIdentityExchange({
    this.identity = const CompanionIdentityClient(),
  });

  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');
  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  void cancel() {
    _cancelled = true;
    _socket?.destroy();
  }

  void _ensureActive() {
    if (_cancelled) {
      throw StateError('PC端末認証をキャンセルしました');
    }
  }

  Future<bool> confirm({
    required String ip,
    required int port,
    required String tlsFingerprint,
    required String pcFingerprint,
    required String invitation,
    required int qrExpires,
    required String phoneNonce,
    required Future<bool> Function() approvePhoneProof,
  }) async {
    if (_busy) throw StateError('認証要求が既に実行中です');
    CompanionPairingClient.validateTarget(ip, port, tlsFingerprint);
    if (!_hex64.hasMatch(pcFingerprint) || !_hex32.hasMatch(invitation) ||
        !_hex64.hasMatch(phoneNonce)) {
      throw const FormatException('PC端末キー・招待ID・認証用乱数が不正です');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (qrExpires <= now || qrExpires - now > 600) {
      throw const FormatException('PC招待QRの期限が切れています');
    }
    _busy = true;
    _cancelled = false;
    try {
      final local = await identity.status();
      _ensureActive();
      if (!local.created || local.fingerprint == null ||
          !_hex64.hasMatch(local.fingerprint!)) {
        throw StateError('先にNetwork Labでスマホの端末キーを作成してください');
      }
      final phoneFp = local.fingerprint!;
      final begin = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/identity-begin',
        json: <String, Object>{
          'protocol': 'pair-identity-v3', 'invitation': invitation,
          'phone_nonce': phoneNonce, 'phone_fp': phoneFp,
        },
      );
      _ensureActive();
      if (begin.length != 6 ||
          begin['status'] != 'challenge' ||
          begin['protocol'] != 'pair-identity-v3' ||
          begin['phone_nonce'] != phoneNonce ||
          begin['pc_nonce'] is! String ||
          !_hex64.hasMatch(begin['pc_nonce'] as String) ||
          begin['expires'] is! int ||
          begin['pc_proof'] is! Map) {
        throw const FormatException('PCのチャレンジが不正です');
      }
      final pcNonce = begin['pc_nonce'] as String;
      final expiry = begin['expires'] as int;
      final current = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiry <= current || expiry > qrExpires || expiry - current > 90) {
        throw const FormatException('PCの認証期限が不正です');
      }
      final pcProof = CompanionIdentityClient.parseProof(
        begin['pc_proof'] as Map<dynamic, dynamic>,
      );
      final verified = await identity.verifyPcProof(
        proof: pcProof,
        pcFingerprint: pcFingerprint,
        invitation: invitation,
        tlsFingerprint: tlsFingerprint,
        phoneFingerprint: phoneFp,
        phoneNonce: phoneNonce,
        expiresUnix: expiry,
      );
      _ensureActive();
      if (!verified) {
        throw StateError('PC固有の公開鍵と署名を確認できません');
      }
      // Android user consents again AFTER the pinned PC proof is verified.
      if (!await approvePhoneProof()) {
        throw StateError('スマホ側で端末署名を拒否しました');
      }
      _ensureActive();
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
        throw const FormatException('確認中に端末認証の期限が切れました');
      }
      final phoneProof = await identity.signPhoneProof(
        invitation: invitation,
        tlsFingerprint: tlsFingerprint,
        pcFingerprint: pcFingerprint,
        pcNonce: pcNonce,
        expiresUnix: expiry,
      );
      _ensureActive();
      final result = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/identity-finish',
        json: <String, Object>{
          'protocol': 'pair-identity-v3', 'invitation': invitation,
          'phone_fp': phoneFp, 'phone_proof': phoneProof,
        },
      );
      _ensureActive();
      if (result.length != 4 ||
          result['status'] != 'approved' ||
          result['protocol'] != 'pair-identity-v3' ||
          result['phone_nonce'] != phoneNonce ||
          result['pc_nonce'] != pcNonce) {
        throw const FormatException('PC側の完了確認が不正です');
      }
      return true;
    } finally {
      _socket?.destroy();
      _socket = null;
      _busy = false;
    }
  }

  Future<Map<String, dynamic>> _post({
    required String ip,
    required int port,
    required String tlsPin,
    required String path,
    required Map<String, Object> json,
  }) async {
    _ensureActive();
    if (_socket != null) throw StateError('同時接続は許可されません');
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        ip, port, timeout: const Duration(seconds: 6),
        onBadCertificate: (cert) =>
            sha256.convert(cert.der).toString() == tlsPin,
      );
      _socket = socket;
      _ensureActive();
      final cert = socket.peerCertificate;
      if (cert == null || sha256.convert(cert.der).toString() != tlsPin) {
        throw const HandshakeException('PCのTLS証明書がQRと一致しません');
      }
      final body = utf8.encode(jsonEncode(json));
      if (body.length > 2048) {
        throw const FormatException('端末認証リクエストが大きすぎます');
      }
      final header = 'POST $path HTTP/1.1\r\n'
          'Host: $ip:$port\r\n'
          'Content-Type: application/json\r\n'
          'Cache-Control: no-store\r\n'
          'Connection: close\r\n'
          'Content-Length: ' + body.length.toString() + '\r\n\r\n';
      socket.add(utf8.encode(header));
      socket.add(body);
      await socket.flush();
      final bytes = <int>[];
      await for (final chunk in socket.timeout(const Duration(seconds: 35))) {
        if (bytes.length + chunk.length > 2048) {
          throw const FormatException('PC応答が大きすぎます');
        }
        bytes.addAll(chunk);
      }
      _ensureActive();
      final response = utf8.decode(bytes);
      final cut = response.indexOf('\r\n\r\n');
      if (cut < 0 || cut > 1024) {
        throw const FormatException('PCのHTTPS応答が不正です');
      }
      final headerLines = response.substring(0, cut).split('\r\n');
      final statusLine = headerLines.first;
      if (statusLine != 'HTTP/1.0 200 OK' &&
          statusLine != 'HTTP/1.1 200 OK') {
        throw StateError('PC側で拒否・期限切れになった可能性があります');
      }
      final lengthLines = headerLines.skip(1)
          .where((line) => line.toLowerCase().startsWith('content-length:'))
          .toList();
      if (lengthLines.length != 1) {
        throw const FormatException('PC応答サイズが不正です');
      }
      final length = int.tryParse(lengthLines.single.split(':').last.trim());
      final payload = response.substring(cut + 4);
      if (length == null || length < 1 || length > 1024 ||
          utf8.encode(payload).length != length) {
        throw const FormatException('PC応答長が一致しません');
      }
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('PC応答がJSONオブジェクトではありません');
      }
      return decoded;
    } finally {
      socket?.destroy();
      if (identical(_socket, socket)) _socket = null;
    }
  }
}
