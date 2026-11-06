import 'dart:convert';

import 'package:chappy_player/core/apk_release_history_service.dart';
import 'package:chappy_player/core/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = ApkReleaseHistoryService();

  Map<String, dynamic> release(int build, String version) {
    final tag = 'v$version-b$build';
    return {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'body': 'テストリリース',
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
          {
            'name': 'ChappyPlayer-$abi.apk',
            'digest': 'sha256:${List.filled(64, 'a').join()}',
            'size': 18000000,
            'browser_download_url':
                'https://github.com/mibesamiti-png/chappy-player-updates/'
                'releases/download/$tag/ChappyPlayer-$abi.apk',
          },
      ],
    };
  }

  test('parses official releases and per-ABI APK build codes', () {
    final items = service.parse(jsonEncode([
      release(5, '0.2.0'),
      release(6, '0.2.1'),
    ]));
    expect(items.length, 2);
    expect(items.first.version, '0.2.1');
    expect(items.first.buildNumber, 4006);
    expect(items.first.forAbi('arm64-v8a')!.androidVersionCode, 2006);
    expect(items.first.newerThan(2005, abi: 'arm64-v8a'), isTrue);
    expect(items.first.newerThan(2006, abi: 'arm64-v8a'), isFalse);
    expect(items.last.newerThan(2005, abi: 'arm64-v8a'), isFalse);
  });

  test('ignores nonofficial or incomplete GitHub release assets', () {
    final bad = release(9, '0.2.9');
    (bad['assets'] as List)[0]['browser_download_url'] =
        'https://attacker.example/not-an-apk';
    final unsigned = release(10, '0.3.0');
    (unsigned['assets'] as List)[1]['digest'] = 'sha256:bad';
    final draft = release(11, '0.3.1');
    draft['draft'] = true;
    final items = service.parse(jsonEncode([
      bad, unsigned, draft, release(6, '0.2.1'),
    ]));
    expect(items.length, 1);
    expect(items.single.version, '0.2.1');
  });

  test('rejects malformed GitHub release API response', () {
    expect(() => service.parse('{}'), throwsFormatException);
    expect(() => service.parse(jsonEncode(List.filled(13, {}))),
        throwsFormatException);
  });
  test('Debug prerelease list never mixes with production release history', () {
    final tag = 'debug-v0.1.0-b100022';
    final debug = {
      'tag_name': tag, 'draft': false, 'prerelease': true,
      'body': 'Android Debug APK',
      'assets': [{
        'name': 'ChappyPlayerDebug.apk',
        'digest': 'sha256:${List.filled(64, 'a').join()}',
        'size': 20000000,
        'browser_download_url':
            'https://github.com/mibesamiti-png/chappy-player-updates/releases/download/$tag/ChappyPlayerDebug.apk',
      }],
    };
    final releases = jsonEncode([debug, release(12, '0.2.5')]);
    final testDebug = const ApkReleaseHistoryService(debug: true).parse(releases);
    expect(testDebug.length, 1);
    expect(testDebug.single.packageId, chappyDebugPackageId);
    expect(testDebug.single.buildNumber, 100022);
    expect(testDebug.single.forAbi('arm64-v8a')!.abi, 'universal');
    expect(service.parse(releases).length, 1);
    final malformed = Map<String, dynamic>.from(debug);
    malformed['assets'] = [Map<String, dynamic>.from(
      (debug['assets'] as List).first as Map)..['browser_download_url'] =
          'https://example.com/malicious.apk'];
    expect(const ApkReleaseHistoryService(debug: true)
        .parse(jsonEncode([malformed])), isEmpty);
  });


}
