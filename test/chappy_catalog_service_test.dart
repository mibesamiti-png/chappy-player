import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/chappy_catalog_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sha = 'a' * 64;

  Map<String, Object> entry({
    String id = 'local.chappy.memo',
    String channel = 'stable',
    String version = '1.0.0',
    String? url,
  }) => {
    'id': id,
    'name': 'メモ帳',
    'description': '保存できるシンプルなメモ帳',
    'version': version,
    'channel': channel,
    'url': url ??
        'https://raw.githubusercontent.com/mibesamiti-png/'
        'chappy-apps/main/$channel/memo.chappy',
    'sha256': sha,
    'sizeBytes': 4096,
  };

  String catalog(List<Map<String, Object>> entries) =>
      jsonEncode({'schemaVersion': 1, 'entries': entries});

  test('parses stable/debug channels and compares semantic versions', () {
    final items = ChappyCatalog.parse(catalog([
      entry(),
      entry(channel: 'debug', version: '1.1.0'),
    ]));
    expect(items.forChannel('stable').length, 1);
    expect(items.forChannel('debug').single.version, '1.1.0');
    expect(compareChappyVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareChappyVersions('1.1.0', '1.1.0'), 0);
    expect(compareChappyVersions('0.2.0', '0.3.0'), lessThan(0));
  });

  test('rejects wrong repo, cross-channel files and duplicated IDs', () {
    expect(() => ChappyCatalog.parse(catalog([
      entry(), entry(),
    ])), throwsFormatException);
    expect(() => ChappyCatalog.parse(catalog([
      entry(url: 'https://raw.githubusercontent.com/attacker/evil/main/'
          'stable/memo.chappy'),
    ])), throwsFormatException);
    expect(() => ChappyCatalog.parse(catalog([
      entry(channel: 'debug', url:
          'https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/'
          'main/stable/memo.chappy'),
    ])), throwsFormatException);
    expect(() => ChappyCatalog.parse(catalog([
      entry(url: 'http://raw.githubusercontent.com/mibesamiti-png/'
          'chappy-apps/main/stable/memo.chappy'),
    ])), throwsFormatException);
    expect(() => ChappyCatalog.parse(catalog([
      entry(url: 'https://raw.githubusercontent.com/mibesamiti-png/'
          'chappy-apps/main/stable/../debug/memo.chappy'),
    ])), throwsFormatException);
    expect(() => ChappyCatalog.parse(catalog([
      entry(url: 'https://raw.githubusercontent.com/mibesamiti-png/'
          'chappy-apps/main/stable/memo.chappy?token=secret'),
    ])), throwsFormatException);
  });

  test('downloads a package only with matching SHA-256 and exact size',
      () async {
    final data = List<int>.generate(2048, (i) => i % 251);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(data);
      await request.response.close();
    });
    try {
      final source = Uri.parse(
          'http://127.0.0.1:${server.port}/stable/sample.chappy');
      final item = ChappyCatalogEntry.parse({
        ...entry(url: source.toString()),
        'sha256': sha256.convert(data).toString(),
        'sizeBytes': data.length,
      }, allowLoopbackForTests: true);
      const service = ChappyCatalogService(
          allowInsecureLoopbackForTests: true);
      expect(await service.download(item), data);
      final broken = ChappyCatalogEntry.parse({
        ...entry(url: source.toString()),
        'sha256': 'f' * 64,
        'sizeBytes': data.length,
      }, allowLoopbackForTests: true);
      await expectLater(service.download(broken), throwsFormatException);
      final truncated = ChappyCatalogEntry.parse({
        ...entry(url: source.toString()),
        'sha256': sha256.convert(data).toString(),
        'sizeBytes': data.length + 5,
      }, allowLoopbackForTests: true);
      await expectLater(service.download(truncated), throwsFormatException);
    } finally {
      await server.close(force: true);
    }
  });

  test('fetches bounded public catalog JSON via test loopback', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(catalog([]));
      await request.response.close();
    });
    try {
      const service = ChappyCatalogService(
          allowInsecureLoopbackForTests: true);
      final data = await service.fetch(source: Uri.parse(
          'http://127.0.0.1:${server.port}/catalog.json'));
      expect(data.entries, isEmpty);
      await expectLater(
        const ChappyCatalogService().fetch(source: Uri.parse(
            'http://127.0.0.1:${server.port}/catalog.json')),
        throwsFormatException,
      );
    } finally {
      await server.close(force: true);
    }
  });
}
