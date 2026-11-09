import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// File transfer is intentionally a DIFFERENT permission from pc.status.read.
class PcFileOffer {
  static const protocol = 'pc-file-receive-v1';
  static const maxBytes = 4 * 1024 * 1024;
  static const chunkBytes = 16 * 1024;

  final String fileName;
  final int sizeBytes;
  final String sha256Hex;
  final int chunkSize;

  const PcFileOffer({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.chunkSize,
  });

  static final _hash = RegExp(r'^[0-9a-f]{64}$');
  static final _forbidden = RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]');

  static PcFileOffer parse(Map<dynamic, dynamic> input) {
    const fields = <String>{
      'file_name', 'size_bytes', 'sha256', 'chunk_bytes',
    };
    if (input.length != fields.length ||
        input.keys.toSet().difference(fields).isNotEmpty) {
      throw const FormatException('転送ファイルの仕様が不正です');
    }
    final name = input['file_name'];
    final size = input['size_bytes'];
    final hash = input['sha256'];
    final chunk = input['chunk_bytes'];
    if (name is! String || name.isEmpty || name.length > 96 ||
        name == '.' || name == '..' ||
        name.endsWith(' ') || name.endsWith('.') ||
        _forbidden.hasMatch(name) ||
        utf8.encode(name).length > 180 ||
        size is! int || size < 1 || size > maxBytes ||
        hash is! String || !_hash.hasMatch(hash) ||
        chunk is! int || chunk != chunkBytes) {
      throw const FormatException('転送ファイル名・容量・ダイジェストが不正です');
    }
    return PcFileOffer(
      fileName: name,
      sizeBytes: size,
      sha256Hex: hash,
      chunkSize: chunk,
    );
  }

  bool matches(PcFileOffer other) =>
      fileName == other.fileName &&
      sizeBytes == other.sizeBytes &&
      sha256Hex == other.sha256Hex &&
      chunkSize == other.chunkSize;
}

class PcReceivedFile {
  final PcFileOffer offer;
  final Uint8List bytes;
  const PcReceivedFile({required this.offer, required this.bytes});
}

/// Must match Windows file_send_once.scoped_nonce exactly; cannot be a QR-v3
/// identity or PC status signature for a different operation.
String pcFileScopedNonce(String rawHex) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHex)) {
    throw const FormatException('ファイル転送専用の認証乱数が不正です');
  }
  final payload = <int>[
    ...utf8.encode('CHAPPY-PC-FILE-RECEIVE-V1'),
    0,
    for (var i = 0; i < rawHex.length; i += 2)
      int.parse(rawHex.substring(i, i + 2), radix: 16),
  ];
  return sha256.convert(payload).toString();
}

/// Accept only the next, exactly sized base64 block. No null gaps, duplicate
/// offsets, oversized chunks, invalid padding or non-final truncated blocks.
Uint8List parsePcFileChunk({
  required Map<dynamic, dynamic> response,
  required int expectedOffset,
  required int fileSize,
}) {
  const fields = <String>{
    'protocol', 'status', 'offset', 'next_offset', 'data', 'done',
  };
  final payload = response['data'];
  final next = response['next_offset'];
  final done = response['done'];
  if (response.length != fields.length ||
      response.keys.toSet().difference(fields).isNotEmpty ||
      response['protocol'] != PcFileOffer.protocol ||
      response['status'] != 'chunk' ||
      response['offset'] is! int ||
      response['offset'] != expectedOffset ||
      next is! int || next <= expectedOffset || next > fileSize ||
      payload is! String ||
      payload.isEmpty || payload.length > 22000 ||
      !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(payload) ||
      done is! bool ||
      done != (next == fileSize)) {
    throw const FormatException('ファイル転送のチャンクが不正です');
  }
  Uint8List bytes;
  try {
    bytes = base64.decode(payload);
  } on FormatException {
    throw const FormatException('ファイル転送のbase64が不正です');
  }
  if (bytes.length != next - expectedOffset ||
      bytes.length > PcFileOffer.chunkBytes ||
      (done == false && bytes.length != PcFileOffer.chunkBytes)) {
    throw const FormatException('ファイルのチャンクサイズが不正です');
  }
  return bytes;
}

void verifyPcReceivedFile(PcFileOffer offer, Uint8List bytes) {
  if (bytes.length != offer.sizeBytes ||
      sha256.convert(bytes).toString() != offer.sha256Hex) {
    throw const FormatException('転送したファイルのSHA-256が一致しません');
  }
}
