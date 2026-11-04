import 'package:chappy_player/core/apk_upgrade_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ApkCompatibilityResult result(String code, {bool compatible = false}) =>
      ApkCompatibilityResult.fromNative({
        'compatible': compatible,
        'code': code,
        'installedBuild': 10,
        'candidateBuild': 11,
      });

  test('accepts exact signer and newer version', () {
    final check = result('COMPATIBLE', compatible: true);
    expect(check.compatible, isTrue);
    expect(check.installedBuild, 10);
    expect(check.candidateBuild, 11);
  });

  test('blocks unsafe signer mismatch with clear data-loss warning', () {
    final check = result('SIGNATURE_MISMATCH');
    expect(check.compatible, isFalse);
    expect(check.userMessage, contains('署名鍵'));
    expect(check.userMessage, contains('バックアップ'));
    expect(check.userMessage, contains('アンインストール'));
  });

  test('rejects equal or downgraded version numbers', () {
    final check = result('VERSION_NOT_NEWER');
    expect(check.userMessage, contains('バージョン番号'));
  });

  test('rejects broken native response', () {
    expect(() => ApkCompatibilityResult.fromNative({
      'compatible': 'not a bool',
      'code': 'COMPATIBLE',
      'installedBuild': 10,
      'candidateBuild': 11,
    }), throwsFormatException);
  });
}
