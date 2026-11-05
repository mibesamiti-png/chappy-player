import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/local_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serves page with bootstrap and restrictive CSP', () async {
    final dir = Directory.systemTemp.createTempSync('chappy_server_test_');
    final server = LocalAppServer(dir);
    try {
      File('${dir.path}/index.html').writeAsStringSync('<html><head></head><body>OK</body></html>');
      await server.start();
      final client = HttpClient();
      final request = await client.getUrl(server.url);
      final response = await request.close();
      final content = await utf8.decoder.bind(response).join();
      expect(response.statusCode, 200);
      expect(content, contains('/__chappy_boot.js'));
      expect(content, contains('/__chappy_media.js'));
      expect(content.indexOf('/__chappy_media.js'),
          lessThan(content.indexOf('/__chappy_boot.js')));
      final mediaResponse = await (await client.getUrl(
          server.url.resolve('/__chappy_media.js'))).close();
      final mediaSource = await utf8.decoder.bind(mediaResponse).join();
      expect(mediaResponse.statusCode, HttpStatus.ok);
      expect(mediaSource, contains('getUserMedia'));
      expect(mediaSource, contains('pagehide'));
      expect(mediaSource, contains('track.stop()'));
      expect(response.headers.value('content-security-policy'), contains("connect-src 'none'"));
      client.close();
    } finally {
      await server.close();
      dir.deleteSync(recursive: true);
    }
  });
  test('sample memo resources are reachable on the loopback host', () async {
    final server = LocalAppServer(Directory('sample_apps/memo'));
    final client = HttpClient();
    try {
      await server.start();
      for (final resource in ['index.html', 'main.js', 'style.css']) {
        final request = await client.getUrl(server.url.resolve(resource));
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: resource);
        final body = await utf8.decoder.bind(response).join();
        expect(body.isNotEmpty, isTrue, reason: resource);
        if (resource == 'index.html') {
          expect(response.headers.contentType?.charset, 'utf-8');
          expect(body, contains('メモ帳'));
          expect(body, contains('/__chappy_boot.js'));
        }
      }
    } finally {
      client.close(force: true);
      await server.close();
    }
  });

}
