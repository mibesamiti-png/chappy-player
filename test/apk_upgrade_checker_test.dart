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

  test('parses installer handoff without calling it an installed update', () {
    final handoff = InstallerHandoff.fromNative({
      'status': 'installer_opened',
    });
    expect(handoff.installerOpened, isTrue);
    expect(handoff.needsPermission, isFalse);
    final settings = InstallerHandoff.fromNative({
      'status': 'permission_required',
    });
    expect(settings.needsPermission, isTrue);
    expect(settings.installerOpened, isFalse);
  });

  test('rejects invalid native installer statuses and honors blocks', () {
    final blocked = InstallerHandoff.fromNative({
      'status': 'blocked',
      'code': 'SIGNATURE_MISMATCH',
    });
    expect(blocked.installerOpened, isFalse);
    expect(blocked.code, 'SIGNATURE_MISMATCH');
    expect(() => InstallerHandoff.fromNative({
      'status': 'installed',
    }), throwsFormatException);
    expect(() => InstallerHandoff.fromNative({
      'status': 'installer_opened',
      'code': 2,
    }), throwsFormatException);
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
