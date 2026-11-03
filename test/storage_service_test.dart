import 'dart:io';

import 'package:chappy_player/core/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late StorageService store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('chappy_storage_test_');
    store = StorageService(directory);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('persists values and isolates app IDs', () async {
    await store.set('local.chappy.memo', 'notes', 'こんにちは');
    expect(await store.get('local.chappy.memo', 'notes'), 'こんにちは');
    expect(await store.get('local.other.app', 'notes'), isNull);
    await store.remove('local.chappy.memo', 'notes');
    expect(await store.get('local.chappy.memo', 'notes'), isNull);
  });
  test('writes to same app are serialized', () async {
    await Future.wait([
      store.set('local.chappy.memo', 'a', 1),
      store.set('local.chappy.memo', 'b', 2),
    ]);
    expect(await store.get('local.chappy.memo', 'a'), 1);
    expect(await store.get('local.chappy.memo', 'b'), 2);
  });
  test('rejects oversized storage', () async {
    expect(() => store.set('local.chappy.memo', 'big', 'X' * (1024 * 1024 + 1)),
        throwsFormatException);
  });
}
