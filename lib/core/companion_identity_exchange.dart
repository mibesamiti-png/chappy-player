import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/companion_identity_client.dart';
import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:chappy_player/core/pc_pairing_stage.dart';
import 'package:chappy_player/core/pc_status_once.dart';
import 'package:chappy_player/core/pc_file_receive.dart';
import 'package:chappy_player/core/pc_file_upload.dart';
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
    void Function(PcPairingStage stage)? onStage,
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
      onStage?.call(PcPairingStage.identity);
      final local = await identity.status();
      _ensureActive();
      if (!local.created || local.fingerprint == null ||
          !_hex64.hasMatch(local.fingerprint!)) {
        throw StateError('先にNetwork Labでスマホの端末キーを作成してください');
      }
      final phoneFp = local.fingerprint!;
      onStage?.call(PcPairingStage.network);
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
      onStage?.call(PcPairingStage.pcProof);
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
      onStage?.call(PcPairingStage.phoneConsent);
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
      onStage?.call(PcPairingStage.finish);
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

  /// R4C optional read-only retrieval, never automatic after QR-v3 identity.
  /// Windows verifies the previous REAL QR-v3 Android key and requests another
  /// console STATUS consent. Android independently re-verifies the new scoped
  /// PC signature and asks for a fresh on-screen consent before signing.
  Future<PcStatusOnceMetrics> readStatusOnce({
    required String ip,
    required int port,
    required String tlsFingerprint,
    required String pcFingerprint,
    required String invitation,
    required int qrExpires,
    required Future<bool> Function() approvePhoneStatus,
  }) async {
    if (_busy || _cancelled) {
      throw StateError('状態取得の前に新しいQR-v3の本人確認が必要です');
    }
    CompanionPairingClient.validateTarget(ip, port, tlsFingerprint);
    if (!_hex64.hasMatch(pcFingerprint) ||
        !_hex32.hasMatch(invitation)) {
      throw const FormatException('PC状態取得のQRが不正です');
    }
    final current = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (qrExpires <= current || qrExpires - current > 600) {
      throw const FormatException('PC状態取得のQR期限が切れています');
    }
    _busy = true;
    try {
      final phoneStatus = await identity.status();
      _ensureActive();
      if (!phoneStatus.created || phoneStatus.fingerprint == null ||
          !_hex64.hasMatch(phoneStatus.fingerprint!)) {
        throw StateError('スマホ端末鍵が利用できません');
      }
      final phoneFp = phoneStatus.fingerprint!;
      final phoneNonce = CompanionIdentityClient.newNonce();
      final challenge = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/status-begin',
        json: <String, Object>{
          'protocol': 'pc-status-once-v1',
          'invitation': invitation,
          'phone_fp': phoneFp,
          'phone_nonce': phoneNonce,
        },
      );
      _ensureActive();
      if (challenge.length != 5 ||
          challenge['protocol'] != 'pc-status-once-v1' ||
          challenge['status'] != 'challenge' ||
          challenge['pc_nonce'] is! String ||
          !_hex64.hasMatch(challenge['pc_nonce'] as String) ||
          challenge['expires'] is! int ||
          challenge['pc_proof'] is! Map) {
        throw const FormatException('PC状態取得の認証応答が不正です');
      }
      final rawPcNonce = challenge['pc_nonce'] as String;
      final expiry = challenge['expires'] as int;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiry <= now || expiry > qrExpires || expiry - now > 90) {
        throw const FormatException('PC状態取得の認証期限が不正です');
      }
      final validPc = await identity.verifyPcProof(
        proof: CompanionIdentityClient.parseProof(
          challenge['pc_proof'] as Map<dynamic, dynamic>,
        ),
        pcFingerprint: pcFingerprint,
        invitation: invitation,
        tlsFingerprint: tlsFingerprint,
        phoneFingerprint: phoneFp,
        phoneNonce: pcStatusScopedNonce(phoneNonce),
        expiresUnix: expiry,
      );
      _ensureActive();
      if (!validPc) {
        throw StateError('状態取得用のPC署名が一致しません');
      }
      if (!await approvePhoneStatus()) {
        throw StateError('スマホでPC状態取得を拒否しました');
      }
      _ensureActive();
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
        throw const FormatException('状態取得の承認中に期限が切れました');
      }
      final phoneProof = await identity.signPhoneProof(
        invitation: invitation,
        tlsFingerprint: tlsFingerprint,
        pcFingerprint: pcFingerprint,
        pcNonce: pcStatusScopedNonce(rawPcNonce),
        expiresUnix: expiry,
      );
      _ensureActive();
      final result = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/status-finish',
        json: <String, Object>{
          'protocol': 'pc-status-once-v1',
          'invitation': invitation,
          'phone_fp': phoneFp,
          'phone_proof': phoneProof,
        },
      );
      _ensureActive();
      if (result.length != 4 ||
          result['protocol'] != 'pc-status-once-v1' ||
          result['status'] != 'ok' ||
          result['pc_nonce'] != rawPcNonce ||
          result['metrics'] is! Map) {
        throw const FormatException('PC状態の応答が不正です');
      }
      return PcStatusOnceMetrics.parse(result['metrics'] as Map);
    } finally {
      _socket?.destroy();
      _socket = null;
      _busy = false;
    }
  }

  /// Owner-selected PC file download with a NEW scope and two NEW approvals.
  /// This does not grant path access, continuous pairing or a JS bridge API.
  Future<PcReceivedFile> receivePcFileOnce({
    required String ip,
    required int port,
    required String tlsFingerprint,
    required String pcFingerprint,
    required String invitation,
    required int qrExpires,
    required Future<bool> Function(PcFileOffer offer) approvePhoneFile,
    void Function(int received, int total)? onProgress,
  }) async {
    if (_busy || _cancelled) {
      throw StateError('新しいQR-v3でPC本人確認を先に行ってください');
    }
    CompanionPairingClient.validateTarget(ip, port, tlsFingerprint);
    if (!_hex64.hasMatch(pcFingerprint) || !_hex32.hasMatch(invitation)) {
      throw const FormatException('ファイル転送のPC認証情報が不正です');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (qrExpires <= now || qrExpires - now > 600) {
      throw const FormatException('ファイル転送のQR期限が不正です');
    }
    _busy = true;
    try {
      final status = await identity.status();
      _ensureActive();
      if (!status.created || status.fingerprint == null ||
          !_hex64.hasMatch(status.fingerprint!)) {
        throw StateError('スマホの端末署名鍵が利用できません');
      }
      final phoneFp = status.fingerprint!;
      final phoneNonce = CompanionIdentityClient.newNonce();
      const protocol = PcFileOffer.protocol;
      final challenge = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/file-begin',
        json: <String, Object>{
          'protocol': protocol, 'invitation': invitation,
          'phone_fp': phoneFp, 'phone_nonce': phoneNonce,
        },
      );
      _ensureActive();
      if (challenge.length != 6 ||
          challenge['protocol'] != protocol ||
          challenge['status'] != 'challenge' ||
          challenge['pc_nonce'] is! String ||
          !_hex64.hasMatch(challenge['pc_nonce'] as String) ||
          challenge['expires'] is! int ||
          challenge['pc_proof'] is! Map ||
          challenge['file'] is! Map) {
        throw const FormatException('PCのファイル転送応答が不正です');
      }
      final offer = PcFileOffer.parse(challenge['file'] as Map);
      final rawPcNonce = challenge['pc_nonce'] as String;
      final expires = challenge['expires'] as int;
      final current = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expires <= current || expires > qrExpires ||
          expires - current > 240) {
        throw const FormatException('ファイル転送の認証期限が不正です');
      }
      final pcValid = await identity.verifyPcProof(
        proof: CompanionIdentityClient.parseProof(
          challenge['pc_proof'] as Map<dynamic, dynamic>,
        ),
        pcFingerprint: pcFingerprint, invitation: invitation,
        tlsFingerprint: tlsFingerprint, phoneFingerprint: phoneFp,
        phoneNonce: pcFileScopedNonce(phoneNonce), expiresUnix: expires,
      );
      _ensureActive();
      if (!pcValid) {
        throw StateError('ファイル転送用のPC署名が一致しません');
      }
      // A NEW, foreground Android consent shows the exact safe file/size.
      if (!await approvePhoneFile(offer)) {
        throw StateError('スマホ側でファイル受信を拒否しました');
      }
      _ensureActive();
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expires) {
        throw const FormatException('ファイル転送の追加承認が期限切れです');
      }
      final phoneProof = await identity.signPhoneProof(
        invitation: invitation, tlsFingerprint: tlsFingerprint,
        pcFingerprint: pcFingerprint,
        pcNonce: pcFileScopedNonce(rawPcNonce), expiresUnix: expires,
      );
      _ensureActive();
      final ready = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/file-finish',
        json: <String, Object>{
          'protocol': protocol, 'invitation': invitation,
          'phone_fp': phoneFp, 'phone_proof': phoneProof,
        },
      );
      _ensureActive();
      if (ready.length != 6 || ready['protocol'] != protocol ||
          ready['status'] != 'ready' ||
          ready['pc_nonce'] != rawPcNonce ||
          ready['expires'] != expires ||
          ready['ticket'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(ready['ticket'] as String) ||
          ready['file'] is! Map ||
          !offer.matches(PcFileOffer.parse(ready['file'] as Map))) {
        throw const FormatException('PCファイル転送の開始情報が不正です');
      }
      final ticket = ready['ticket'] as String;
      final bytes = BytesBuilder(copy: false);
      var offset = 0;
      onProgress?.call(0, offer.sizeBytes);
      while (offset < offer.sizeBytes) {
        _ensureActive();
        if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expires) {
          throw const FormatException('ファイル転送中に期限が切れました');
        }
        final answer = await _post(
          ip: ip, port: port, tlsPin: tlsFingerprint,
          path: '/v3/file-chunk',
          json: <String, Object>{
            'protocol': protocol, 'ticket': ticket, 'offset': offset,
          },
          maxResponseBytes: 25000,
          maxPayloadBytes: 23000,
        );
        _ensureActive();
        final chunk = parsePcFileChunk(
          response: answer, expectedOffset: offset, fileSize: offer.sizeBytes,
        );
        bytes.add(chunk);
        offset += chunk.length;
        onProgress?.call(offset, offer.sizeBytes);
      }
      final received = Uint8List.fromList(bytes.takeBytes());
      verifyPcReceivedFile(offer, received);
      return PcReceivedFile(offer: offer, bytes: received);
    } finally {
      _socket?.destroy();
      _socket = null;
      _busy = false;
    }
  }

  /// R5B Android -> Windows: a NEW scope, owner-chosen PC destination, and
  /// separate PC RECEIVE and foreground Android consents. This method MUST
  /// only be called after QR-v3 mutual device proof on the trusted host page.
  Future<void> uploadPcFileOnce({
    required String ip,
    required int port,
    required String tlsFingerprint,
    required String pcFingerprint,
    required String invitation,
    required int qrExpires,
    required PcUploadFile file,
    required Future<bool> Function(PcUploadFile file) approvePhoneUpload,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_busy || _cancelled) {
      throw StateError('新しいQR-v3認証が必要です');
    }
    CompanionPairingClient.validateTarget(ip, port, tlsFingerprint);
    if (!_hex64.hasMatch(pcFingerprint) || !_hex32.hasMatch(invitation)) {
      throw const FormatException('送信先PCのQR情報が不正です');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (qrExpires <= now || qrExpires - now > 600) {
      throw const FormatException('送信用QRが期限切れです');
    }
    _busy = true;
    String? activeTicket;
    try {
      final status = await identity.status();
      _ensureActive();
      if (!status.created || status.fingerprint == null ||
          !_hex64.hasMatch(status.fingerprint!)) {
        throw StateError('スマホのKeyStore署名鍵がありません');
      }
      final phoneFp = status.fingerprint!;
      final phoneNonce = CompanionIdentityClient.newNonce();
      final challenge = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/upload-begin',
        json: <String, Object>{
          'protocol': PcUploadFile.protocol,
          'invitation': invitation,
          'phone_fp': phoneFp,
          'phone_nonce': phoneNonce,
          'file_name': file.fileName,
          'size_bytes': file.bytes.length,
          'sha256': file.digest,
        },
      );
      _ensureActive();
      if (challenge.length != 6 ||
          challenge['protocol'] != PcUploadFile.protocol ||
          challenge['status'] != 'challenge' ||
          challenge['pc_nonce'] is! String ||
          !_hex64.hasMatch(challenge['pc_nonce'] as String) ||
          challenge['expires'] is! int ||
          challenge['pc_proof'] is! Map ||
          challenge['file'] is! Map) {
        throw const FormatException('Windowsの送信承認応答が不正です');
      }
      final offered = PcFileOffer.parse(challenge['file'] as Map);
      if (offered.fileName != file.fileName ||
          offered.sizeBytes != file.bytes.length ||
          offered.sha256Hex != file.digest) {
        throw const FormatException('PCが別ファイルを要求しました');
      }
      final rawPcNonce = challenge['pc_nonce'] as String;
      final expiry = challenge['expires'] as int;
      final current = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiry <= current || expiry > qrExpires || expiry - current > 240) {
        throw const FormatException('PC送信承認の期限が不正です');
      }
      final pcVerified = await identity.verifyPcProof(
        proof: CompanionIdentityClient.parseProof(
          challenge['pc_proof'] as Map<dynamic, dynamic>,
        ),
        pcFingerprint: pcFingerprint,
        invitation: invitation,
        tlsFingerprint: tlsFingerprint,
        phoneFingerprint: phoneFp,
        phoneNonce: pcUploadScopedNonce(phoneNonce),
        expiresUnix: expiry,
      );
      _ensureActive();
      if (!pcVerified) {
        throw StateError('Windowsの送信専用署名が一致しません');
      }
      if (!await approvePhoneUpload(file)) {
        throw StateError('Androidでファイル送信を拒否しました');
      }
      _ensureActive();
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
        throw const FormatException('送信の追加承認が期限切れです');
      }
      final phoneProof = await identity.signPhoneProof(
        invitation: invitation, tlsFingerprint: tlsFingerprint,
        pcFingerprint: pcFingerprint,
        pcNonce: pcUploadScopedNonce(rawPcNonce), expiresUnix: expiry,
      );
      _ensureActive();
      final ready = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/upload-finish',
        json: <String, Object>{
          'protocol': PcUploadFile.protocol, 'invitation': invitation,
          'phone_fp': phoneFp, 'phone_proof': phoneProof,
        },
      );
      _ensureActive();
      if (ready.length != 5 ||
          ready['protocol'] != PcUploadFile.protocol ||
          ready['status'] != 'ready' ||
          ready['pc_nonce'] != rawPcNonce ||
          ready['expires'] != expiry ||
          ready['ticket'] is! String ||
          !RegExp(r'^[0-9a-f]{32}
      SecureSocket socket, {int maxBytes = 2048}) async {
    final bytes = <int>[];
    await for (final chunk in socket) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('PC応答が大きすぎます');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<Map<String, dynamic>> _post({
    required String ip,
    required int port,
    required String tlsPin,
    required String path,
    required Map<String, Object> json,
    int maxResponseBytes = 2048,
    int maxPayloadBytes = 1024,
    int maxRequestBytes = 2048,
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
      if (body.length > maxRequestBytes) {
        throw const FormatException('PCへのリクエストが大きすぎます');
      }
      final header = 'POST $path HTTP/1.1\r\n'
          'Host: $ip:$port\r\n'
          'Content-Type: application/json\r\n'
          'Cache-Control: no-store\r\n'
          'Connection: close\r\n'
          'Content-Length: ${body.length}\r\n\r\n';
      socket.add(utf8.encode(header));
      socket.add(body);
      await socket.flush();
      // Absolute wall-clock deadline, not a per-chunk inactivity timeout.
      final bytes = await _readBounded(socket, maxBytes: maxResponseBytes)
          .timeout(const Duration(seconds: 35));
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
      if (length == null || length < 1 || length > maxPayloadBytes ||
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
).hasMatch(ready['ticket'] as String)) {
        throw const FormatException('Windowsの送信開始情報が不正です');
      }
      activeTicket = ready['ticket'] as String;
      var offset = 0;
      onProgress?.call(0, file.bytes.length);
      while (offset < file.bytes.length) {
        _ensureActive();
        if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
          throw const FormatException('送信中に期限切れになりました');
        }
        final end = offset + PcFileOffer.chunkBytes > file.bytes.length
            ? file.bytes.length : offset + PcFileOffer.chunkBytes;
        final chunk = Uint8List.sublistView(file.bytes, offset, end);
        final ack = await _post(
          ip: ip, port: port, tlsPin: tlsFingerprint,
          path: '/v3/upload-chunk',
          json: <String, Object>{
            'protocol': PcUploadFile.protocol,
            'ticket': activeTicket,
            'offset': offset,
            'data': base64Encode(chunk),
          },
          maxRequestBytes: 25000,
        );
        _ensureActive();
        validatePcUploadAck(
          ack, expectedOffset: offset, fileLength: file.bytes.length,
        );
        offset = end;
        onProgress?.call(offset, file.bytes.length);
      }
      final result = await _post(
        ip: ip, port: port, tlsPin: tlsFingerprint,
        path: '/v3/upload-commit',
        json: <String, Object>{
          'protocol': PcUploadFile.protocol,
          'ticket': activeTicket,
          'size_bytes': file.bytes.length,
          'sha256': file.digest,
        },
      );
      _ensureActive();
      if (result.length != 4 ||
          result['protocol'] != PcUploadFile.protocol ||
          result['status'] != 'saved' ||
          result['size_bytes'] != file.bytes.length ||
          result['sha256'] != file.digest) {
        throw const FormatException('Windowsの保存完了証明が不正です');
      }
      activeTicket = null;
    } finally {
      // If a chunk timed out, the owner can stop the server, and its memory
      // buffer is zeroed. The cancellable one-time ticket is never persisted.
      _socket?.destroy();
      _socket = null;
      _busy = false;
    }
  }

  static Future<List<int>> _readBounded(
      SecureSocket socket, {int maxBytes = 2048}) async {
    final bytes = <int>[];
    await for (final chunk in socket) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('PC応答が大きすぎます');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<Map<String, dynamic>> _post({
    required String ip,
    required int port,
    required String tlsPin,
    required String path,
    required Map<String, Object> json,
    int maxResponseBytes = 2048,
    int maxPayloadBytes = 1024,
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
          'Content-Length: ${body.length}\r\n\r\n';
      socket.add(utf8.encode(header));
      socket.add(body);
      await socket.flush();
      // Absolute wall-clock deadline, not a per-chunk inactivity timeout.
      final bytes = await _readBounded(socket, maxBytes: maxResponseBytes)
          .timeout(const Duration(seconds: 35));
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
      if (length == null || length < 1 || length > maxPayloadBytes ||
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
