import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/pc_file_receive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PC/Android file scoped nonce is not a QR-v3 identity nonce', () {
    final value = 'fa' * 32;
    final scoped = pcFileScopedNonce(value);
    expect(scoped, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(scoped, isNot(value));
    expect(() => pcFileScopedNonce('ABC'), throwsFormatException);
  });

  test('safe bounded selected file metadata, no arbitrary paths', () {
    final bytes = Uint8List.fromList(utf8.encode('Hello Chappy'));
    final offer = PcFileOffer.parse({
      'file_name': 'memo.txt',
      'size_bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'chunk_bytes': PcFileOffer.chunkBytes,
    });
    expect(offer.fileName, 'memo.txt');
    expect(offer.sizeBytes, bytes.length);
    verifyPcReceivedFile(offer, bytes);
    final badDigest = Uint8List.fromList(utf8.encode('Wrong bytes!'));
    expect(() => verifyPcReceivedFile(offer, badDigest), throwsFormatException);
    for (final badName in [
      '../private.txt', '/etc/passwd', r'..\secret.txt',
      '.', '..', 'file\nname.txt', 'trailing.', 'end ',
    ]) {
      expect(() => PcFileOffer.parse({
        'file_name': badName,
        'size_bytes': bytes.length,
        'sha256': offer.sha256Hex,
        'chunk_bytes': PcFileOffer.chunkBytes,
      }), throwsFormatException, reason: badName);
    }
  });

  test('chunk offset, final flag, exact length and base64 are strict', () {
    final chunk = Uint8List.fromList([1, 2, 3]);
    final response = <String, dynamic>{
      'protocol': PcFileOffer.protocol,
      'status': 'chunk',
      'offset': 0,
      'next_offset': 3,
      'data': base64Encode(chunk),
      'done': true,
    };
    expect(parsePcFileChunk(
      response: response, expectedOffset: 0, fileSize: 3,
    ), chunk);
    for (final bad in [
      {...response, 'offset': 1},
      {...response, 'next_offset': 4},
      {...response, 'data': '!!'},
      {...response, 'done': false},
      {...response, 'readPath': '/private'},
      {...response}..remove('data'),
    ]) {
      expect(() => parsePcFileChunk(
        response: bad, expectedOffset: 0, fileSize: 3,
      ), throwsFormatException);
    }
  });
}
