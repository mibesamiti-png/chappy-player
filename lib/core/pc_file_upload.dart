import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/pc_file_receive.dart';
import 'package:crypto/crypto.dart';

/// Independent from pc.file.receive and pc.status.read. One selected file only.
class PcUploadFile {
  static const protocol = 'pc-file-upload-v1';
  final String fileName;
  final Uint8List bytes;
  final String digest;
  PcUploadFile({required this.fileName, required this.bytes})
      : digest = sha256.convert(bytes).toString() {
    // Reuse the same safe filename/size contract as bounded PC downloads.
    PcFileOffer.parse(<String, Object>{
      'file_name': fileName,
      'size_bytes': bytes.length,
      'sha256': digest,
      'chunk_bytes': PcFileOffer.chunkBytes,
    });
  }

  Map<String, Object> get offer => <String, Object>{
    'file_name': fileName,
    'size_bytes': bytes.length,
    'sha256': digest,
    'chunk_bytes': PcFileOffer.chunkBytes,
  };
}

String pcUploadScopedNonce(String rawHex) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHex)) {
    throw const FormatException('送信専用の認証用乱数が不正です');
  }
  final payload = <int>[
    ...utf8.encode('CHAPPY-PC-FILE-UPLOAD-V1'),
    0,
    for (var i = 0; i < rawHex.length; i += 2)
      int.parse(rawHex.substring(i, i + 2), radix: 16),
  ];
  return sha256.convert(payload).toString();
}

void validatePcUploadAck(
  Map<dynamic, dynamic> raw, {
  required int expectedOffset,
  required int fileLength,
}) {
  const keys = <String>{'protocol', 'status', 'next_offset', 'done'};
  final next = raw['next_offset'];
  final complete = raw['done'];
  if (raw.length != keys.length ||
      raw.keys.toSet().difference(keys).isNotEmpty ||
      raw['protocol'] != PcUploadFile.protocol ||
      raw['status'] != 'received' ||
      next is! int || next <= expectedOffset || next > fileLength ||
      next - expectedOffset !=
          (fileLength - expectedOffset < PcFileOffer.chunkBytes
              ? fileLength - expectedOffset : PcFileOffer.chunkBytes) ||
      complete is! bool || complete != (next == fileLength)) {
    throw const FormatException('Windowsのチャンク確認応答が不正です');
  }
}
