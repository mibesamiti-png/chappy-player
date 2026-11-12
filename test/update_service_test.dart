import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String repeat64(String part) => List.filled(64, part).join();
  String feed({
    int build = 12,
    String packageId = 'dev.chappy.chappy_player',
    List<Map<String, Object>>? artifacts,
  }) => jsonEncode({
    'schemaVersion': 1,
    'packageId': packageId,
    'version': '0.2.0',
    'buildNumber': build,
    'releaseNotes': 'Improved startup and saving',
    'artifacts': artifacts ?? [{
      'abi': 'arm64-v8a',
      'url': 'https://updates.example.org/chappy-arm64.apk',
      'sha256': repeat64('a'),
      'sizeBytes': 4096,
    }, {
      'abi': 'universal',
      'url': 'https://updates.example.org/chappy-universal.apk',
      'sha256': repeat64('b'),
      'sizeBytes': 12000,
    }],
  });

  test('accepts valid feed and selects CPU-specific APK', () {
    final item = UpdateRelease.parse(feed());
    expect(item.newerThan(11), isTrue);
    expect(item.newerThan(12), isFalse);
    expect(item.forAbi('arm64-v8a')!.abi, 'arm64-v8a');
    expect(item.forAbi('armeabi-v7a')!.abi, 'universal');
    expect(item.artifacts.length, 2);
  });

  test('split-ABI versionCodes correctly detect Android upgrades', () {
    final item = UpdateRelease.parse(feed(build: 4006, artifacts: [
      {
        'abi': 'arm64-v8a',
        'url': 'https://updates.example.org/chappy-arm64.apk',
        'sha256': repeat64('a'),
        'sizeBytes': 4096,
        'androidVersionCode': 2006,
      },
      {
        'abi': 'armeabi-v7a',
        'url': 'https://updates.example.org/chappy-arm.apk',
        'sha256': repeat64('b'),
        'sizeBytes': 4096,
        'androidVersionCode': 1006,
      },
      {
        'abi': 'x86_64',
        'url': 'https://updates.example.org/chappy-x86.apk',
        'sha256': repeat64('c'),
        'sizeBytes': 4096,
        'androidVersionCode': 4006,
      },
    ]));
    expect(item.newerThan(2005, abi: 'arm64-v8a'), isTrue);
    expect(item.newerThan(2006, abi: 'arm64-v8a'), isFalse);
    expect(item.newerThan(4005, abi: 'x86_64'), isTrue);
    expect(item.newerThan(4006, abi: 'x86_64'), isFalse);
    expect(item.newerThan(1006, abi: 'armeabi-v7a'), isFalse);
    expect(item.forAbi('arm64-v8a')!.androidVersionCode, 2006);
  });

  test('rejects wrong app, unsafe URLs, duplicated ABIs and invalid hash', () {
    expect(() => UpdateRelease.parse(feed(packageId: 'not.chappy')),
        throwsFormatException);
    expect(() => UpdateRelease.parse(feed(artifacts: [{
      'abi': 'arm64-v8a',
      'url': 'http://example.org/insecure.apk',
      'sha256': repeat64('a'),
      'sizeBytes': 4096,
    }])), throwsFormatException);
    expect(() => UpdateRelease.parse(feed(artifacts: [{
      'abi': 'arm64-v8a',
      'url': 'https://user:pass@example.org/file.apk',
      'sha256': repeat64('a'),
      'sizeBytes': 4096,
    }])), throwsFormatException);
    expect(() => UpdateRelease.parse(feed(artifacts: [{
      'abi': 'arm64-v8a',
      'url': 'https://example.org/file.apk',
      'sha256': 'broken',
      'sizeBytes': 4096,
    }])), throwsFormatException);
    expect(() => UpdateRelease.parse(feed(artifacts: [
      {
        'abi': 'arm64-v8a',
        'url': 'https://example.org/a.apk',
        'sha256': repeat64('a'),
        'sizeBytes': 4096,
      },
      {
        'abi': 'arm64-v8a',
        'url': 'https://example.org/b.apk',
        'sha256': repeat64('b'),
        'sizeBytes': 4096,
      },
    ])), throwsFormatException);
  });

  test('download validates the exact SHA-256 and rejects tampered APKs',
      () async {
    final bytes = List<int>.generate(4096, (index) => index % 256);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final temp = await Directory.systemTemp.createTemp('chappy_updates_test_');
    try {
      final url = Uri.parse('http://127.0.0.1:${server.port}/file.apk');
      final expected = sha256.convert(bytes).toString();
      final service = UpdateService(allowInsecureLoopbackForTests: true);
      final good = UpdateArtifact('arm64-v8a', url, expected, bytes.length);
      final path = await service.download(good, temp);
      expect(await path.readAsBytes(), bytes);
      expect(path.path, endsWith('chappy-update.apk'));

      final bad = UpdateArtifact('arm64-v8a', url, repeat64('f'), bytes.length);
      await expectLater(service.download(bad, temp), throwsFormatException);
      expect(await File('${temp.path}/chappy-update.part').exists(), isFalse);
    } finally {
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });

  test('only approved GitHub release asset redirects are allowed', () {
    final original = Uri.parse(
        'https://github.com/mibesamiti-png/chappy-player-updates/'
        'releases/download/v0.2.0-b15/ChappyPlayer-arm64-v8a.apk');
    expect(isSafeUpdateRedirect(original, Uri.parse(
        'https://release-assets.githubusercontent.com/assets/123?token=x')),
        isTrue);
    expect(isSafeUpdateRedirect(original, Uri.parse(
        'https://objects.githubusercontent.com/assets/123?token=x')),
        isTrue);
    expect(isSafeUpdateRedirect(original, Uri.parse(
        'https://attacker.example/malware.apk')), isFalse);
    expect(isSafeUpdateRedirect(original, Uri.parse(
        'http://release-assets.githubusercontent.com/malware.apk')), isFalse);
    expect(isSafeUpdateRedirect(original, Uri.parse(
        'https://user:pass@objects.githubusercontent.com/malware.apk')), isFalse);
  });

  test('follows test-only loopback redirect and still verifies SHA-256',
      () async {
    final data = List<int>.generate(4096, (i) => (i * 7) % 256);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/start.apk') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
            HttpHeaders.locationHeader, '/release.apk');
      } else {
        request.response.add(data);
      }
      await request.response.close();
    });
    final root = await Directory.systemTemp.createTemp(
        'chappy_update_redirect_');
    try {
      final uri = Uri.parse(
          'http://127.0.0.1:${server.port}/start.apk');
      final artifact = UpdateArtifact('arm64-v8a', uri,
          sha256.convert(data).toString(), data.length);
      final file = await UpdateService(
          allowInsecureLoopbackForTests: true).download(artifact, root);
      expect(await file.readAsBytes(), data);
    } finally {
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });

  test('does not accept plain HTTP outside tests', () async {
    final service = UpdateService();
    await expectLater(
      service.fetch(Uri.parse('http://127.0.0.1:9999/feed.json')),
      throwsFormatException,
    );
  });

  test('fetches small JSON feed with loopback only in tests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.response.write(feed(build: 7));
      await request.response.close();
    });
    try {
      final service = UpdateService(allowInsecureLoopbackForTests: true);
      final item = await service.fetch(
          Uri.parse('http://127.0.0.1:${server.port}/feed.json'));
      expect(item.buildNumber, 7);
      expect(item.forAbi('arm64-v8a'), isNotNull);
    } finally {
      await server.close(force: true);
    }
  });
  test('accepts only matching Debug channel package ID', () {
    final debugFeed = feed(build: 21,
        packageId: chappyDebugPackageId,
        artifacts: [{
          'abi': 'universal',
          'url': 'https://github.com/mibesamiti-png/chappy-player-updates/releases/download/debug-v0.1.0-b21/ChappyPlayerDebug.apk',
          'sha256': repeat64('a'), 'sizeBytes': 4000,
          'androidVersionCode': 21,
        }]);
    expect(() => UpdateRelease.parse(debugFeed), throwsFormatException);
    final debug = UpdateRelease.parse(debugFeed,
        expectedPackageId: chappyDebugPackageId);
    expect(debug.forAbi('arm64-v8a')!.abi, 'universal');
    expect(debug.newerThan(20, abi: 'arm64-v8a'), true);
    expect(debug.newerThan(21, abi: 'arm64-v8a'), false);
    expect(() => UpdateRelease.parse(feed(),
        expectedPackageId: chappyDebugPackageId), throwsFormatException);
  });


}
