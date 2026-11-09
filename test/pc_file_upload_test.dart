import 'dart:typed_data';

import 'package:chappy_player/core/pc_file_upload.dart';
import 'package:chappy_player/core/pc_file_receive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upload has independent scoped nonce from QR-v3 and PC downloads', () {
    final raw = '12' * 32;
    expect(pcUploadScopedNonce(raw), isNot(raw));
    expect(pcUploadScopedNonce(raw), isNot(pcFileScopedNonce(raw)));
    expect(() => pcUploadScopedNonce('BAD'), throwsFormatException);
  });

  test('only a single bounded safe basename is offered', () {
    final file = PcUploadFile(
      fileName: 'demo.bin', bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(file.offer['size_bytes'], 3);
    expect(file.digest.length, 64);
    for (final name in ['../secret', '/etc/password', r'..\secret', '.', 'bad.']) {
      expect(
        () => PcUploadFile(fileName: name, bytes: Uint8List.fromList([7])),
        throwsFormatException,
      );
    }
    expect(
      () => PcUploadFile(
        fileName: 'large.bin', bytes: Uint8List(PcFileOffer.maxBytes + 1),
      ),
      throwsFormatException,
    );
  });

  test('ack strict sequential offsets and no additional metadata', () {
    final answer = <String, Object>{
      'protocol': PcUploadFile.protocol, 'status': 'received',
      'next_offset': 3, 'done': true,
    };
    validatePcUploadAck(answer, expectedOffset: 0, fileLength: 3);
    for (final bad in [
      {...answer, 'next_offset': 2},
      {...answer, 'next_offset': 4},
      {...answer, 'done': false},
      {...answer, 'path': 'C:/private'},
      {...answer, 'status': 'ok'},
    ]) {
      expect(
        () => validatePcUploadAck(bad, expectedOffset: 0, fileLength: 3),
        throwsFormatException,
      );
    }
  });
}
