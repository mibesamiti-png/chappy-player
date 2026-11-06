import 'package:chappy_player/core/package_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = '''{
    "formatVersion": 1,
    "id": "local.chappy.memo",
    "name": "メモ帳",
    "version": "0.1.0",
    "entry": "index.html",
    "permissions": []
  }''';

  test('valid manifest', () {
    final app = ChappyPackage.parse(valid);
    expect(app.id, 'local.chappy.memo');
    expect(app.entry, 'index.html');
  });
  test('accept explicitly declared camera and microphone', () {
    final app = ChappyPackage.parse(valid.replaceFirst('"permissions": []',
        '"permissions": ["camera", "microphone"]'));
    expect(app.permissions, ['camera', 'microphone']);
    expect(chappyPermissionsLabel(app.permissions), 'カメラ・マイク');
    expect(chappyPermissionsLabel([]), '追加権限なし');
    final tools = ChappyPackage.parse(valid.replaceFirst(
        '"permissions": []', '"permissions": ["motion", "haptics"]'));
    expect(tools.permissions, ['motion', 'haptics']);
    expect(chappyPermissionsLabel(tools.permissions), '動きセンサー・振動');
  });
  test('reject unknown, duplicate and malformed privileges', () {
    for (final list in [
      '["location"]',
      '["camera", "camera"]',
      '["camera", "location"]',
      '["microphone", 42]',
      '"camera"',
    ]) {
      expect(() => ChappyPackage.parse(
          valid.replaceFirst('"permissions": []', '"permissions": $list')),
          throwsFormatException);
    }
  });
  test('reject unsafe IDs', () {
    expect(() => ChappyPackage.parse(valid.replaceFirst('local.chappy.memo',
        '../../private')), throwsFormatException);
  });
  test('reject incompatible format', () {
    expect(() => ChappyPackage.parse(valid.replaceFirst('"formatVersion": 1',
        '"formatVersion": 99')), throwsFormatException);
  });
  test('reject traversal and absolute paths', () {
    expect(isSafeArchivePath('../escape'), false);
    expect(isSafeArchivePath('assets/../../escape'), false);
    expect(isSafeArchivePath('/root.txt'), false);
    expect(isSafeArchivePath(r'C:\Windows\test'), false);
    expect(isSafeArchivePath('assets/icon.png'), true);
  });
}
