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
      expect(response.headers.value('content-security-policy'), contains("connect-src 'none'"));
      client.close();
    } finally {
      await server.close();
      dir.deleteSync(recursive: true);
    }
  });
}
