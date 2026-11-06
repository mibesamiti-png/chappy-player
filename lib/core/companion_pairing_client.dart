import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A ONE-TIME proof of PC ownership, not lasting device authorization.
/// The user enters the full fingerprint shown by the PC, then PC approves.
class CompanionPairingClient {
  SecureSocket? _socket;
  bool _cancelled = false;

  static String normalizeFingerprint(String input) {
    final value = input.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('PC画面のSHA-256指紋64文字が必要です');
    }
    return value;
  }

  static bool isPrivateIpv4(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static String newNonce() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String confirmationCode(String nonce) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce)) {
      throw const FormatException('Invalid confirmation nonce');
    }
    final bytes = <int>[
      for (var i = 0; i < nonce.length; i += 2)
        int.parse(nonce.substring(i, i + 2), radix: 16),
    ];
    return sha256.convert(bytes).toString().substring(0, 6).toUpperCase();
  }

  static void validateTarget(String ip, int port, String fingerprint) {
    if (!isPrivateIpv4(ip) || port < 1 || port > 65535) {
      throw const FormatException('プライベートIPv4と有効なポートを指定してください');
    }
    normalizeFingerprint(fingerprint);
  }

  Future<bool> confirm({
    required String ip,
    required int port,
    required String fingerprint,
    required String nonce,
    String? invitation,
  }) async {
    validateTarget(ip, port, fingerprint);
    confirmationCode(nonce);
    if (invitation != null && !RegExp(r'^[0-9a-f]{32}$').hasMatch(invitation)) {
      throw const FormatException('QR招待IDが不正です');
    }
    if (_socket != null) throw StateError('すでに接続確認中です');
    _cancelled = false;
    final pin = normalizeFingerprint(fingerprint);
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        ip, port,
        timeout: const Duration(seconds: 6),
        onBadCertificate: (certificate) =>
            sha256.convert(certificate.der).toString() == pin,
      );
      _socket = socket;
      if (_cancelled) throw StateError('確認がキャンセルされました');
      // Even CA-trusted certs must match the exact user-entered pin.
      final cert = socket.peerCertificate;
      if (cert == null || sha256.convert(cert.der).toString() != pin) {
        throw const HandshakeException('PCの証明書指紋が一致しません');
      }
      final body = utf8.encode(jsonEncode(<String, String>{
        'protocol': invitation == null ? 'pair-preview-v1' : 'pair-qr-v2',
        'nonce': nonce,
        if (invitation != null) 'invitation': invitation,
      }));
      final header =
          'POST /v1/pair-preview HTTP/1.1\r\n'
          'Host: $ip:$port\r\n'
          'Content-Type: application/json\r\n'
          'Cache-Control: no-store\r\n'
          'Connection: close\r\n'
          'Content-Length: ${body.length}\r\n\r\n';
      socket.add(utf8.encode(header));
      socket.add(body);
      await socket.flush();
      final response = await _readBounded(socket)
          .timeout(const Duration(seconds: 35));
      if (_cancelled) throw StateError('確認がキャンセルされました');
      return _validateReply(response, nonce, invitation != null);
    } finally {
      socket?.destroy();
      if (identical(_socket, socket)) _socket = null;
    }
  }

  static Future<List<int>> _readBounded(SecureSocket socket) async {
    final bytes = <int>[];
    await for (final chunk in socket) {
      if (bytes.length + chunk.length > 2048) {
        throw const FormatException('PCからの応答が大きすぎます');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  static bool _validateReply(
    List<int> bytes, String nonce, bool qrMode,
  ) {
    final raw = utf8.decode(bytes);
    final split = raw.indexOf('\r\n\r\n');
    if (split < 0 || split > 1024) {
      throw const FormatException('不正なHTTPS応答です');
    }
    final lines = raw.substring(0, split).split('\r\n');
    if (lines.first != 'HTTP/1.0 200 OK' &&
        lines.first != 'HTTP/1.1 200 OK') {
      throw StateError('PC側で拒否されたか、確認が期限切れになりました');
    }
    final lengths = lines.skip(1).where(
      (line) => line.toLowerCase().startsWith('content-length:'),
    ).toList(growable: false);
    if (lengths.length != 1) {
      throw const FormatException('PC応答のサイズが不正です');
    }
    final length = int.tryParse(lengths.single.split(':').last.trim());
    final reply = raw.substring(split + 4);
    if (length == null || length < 1 || length > 1024 ||
        utf8.encode(reply).length != length) {
      throw const FormatException('PC応答のサイズが一致しません');
    }
    final parsed = jsonDecode(reply);
    if (parsed is! Map || parsed['status'] != 'approved' ||
        parsed['protocol'] != (qrMode ? 'pair-qr-v2' : 'pair-preview-v1') ||
        parsed['nonce'] != nonce) {
      throw const FormatException('PCからの承認結果が不正です');
    }
    return true;
  }

  void cancel() {
    _cancelled = true;
    _socket?.destroy();
  }
}
