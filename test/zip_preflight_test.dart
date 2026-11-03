import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/zip_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  test('accepts well-formed ZIP envelope', () {
    expect(() => validateZipEnvelope(fixture('safe.zip')), returnsNormally);
  });
  test('rejects path traversal ZIP', () {
    expect(() => validateZipEnvelope(fixture('traversal.zip')), throwsFormatException);
  });
  test('rejects missing manifest', () {
    expect(() => validateZipEnvelope(fixture('no_manifest.zip')), throwsFormatException);
  });
  test('rejects non-ZIP data', () {
    expect(() => validateZipEnvelope(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
  test('rejects oversized input', () {
    expect(() => validateZipEnvelope(Uint8List(12 * 1024 * 1024 + 1)),
        throwsFormatException);
  });
}
