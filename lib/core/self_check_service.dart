import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/local_app_server.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/core/storage_service.dart';
import 'package:path/path.dart' as p;

class SelfCheckResult {
  final String id;
  final String label;
  final String detail;
  final bool passed;
  final int elapsedMs;

  const SelfCheckResult({
    required this.id,
    required this.label,
    required this.detail,
    required this.passed,
    required this.elapsedMs,
  });
}

/// Checks platform services on the *actual device*, without granting
/// permissions to mini-apps or sending data over a network.
class SelfCheckService {
  final PackageRepository repository;
  final LogStore logs;
  SelfCheckService({required this.repository, required this.logs});

  Future<List<SelfCheckResult>> run() async {
    final results = <SelfCheckResult>[];

    Future<void> check(
      String id,
      String label,
      Future<String> Function() action,
    ) async {
      final timer = Stopwatch()..start();
      try {
        final detail = await action();
        results.add(SelfCheckResult(
          id: id,
          label: label,
          detail: detail,
          passed: true,
          elapsedMs: timer.elapsedMilliseconds,
        ));
      } catch (error) {
        results.add(SelfCheckResult(
          id: id,
          label: label,
          detail: '$error',
          passed: false,
          elapsedMs: timer.elapsedMilliseconds,
        ));
      } finally {
        timer.stop();
      }
    }

    await check('storage', '保存データの読み書き', () async {
      final scratch = await Directory(p.join(
        repository.stagingRoot.path,
        'self_check_storage',
      )).create(recursive: true);
      try {
        final storage = StorageService(scratch);
        await storage.set('local.chappy.selfcheck', 'check', {
          'hello': 'チャッピー',
          'value': 42,
        });
        final value = await storage.get('local.chappy.selfcheck', 'check');
        if (value is! Map || value['hello'] != 'チャッピー' ||
            value['value'] != 42) {
          throw StateError('保存後のデータが一致しません');
        }
        await storage.remove('local.chappy.selfcheck', 'check');
        if (await storage.get('local.chappy.selfcheck', 'check') != null) {
          throw StateError('削除した保存キーが残っています');
        }
        return 'JSONの保存・読み込み・削除が正常';
      } finally {
        if (await scratch.exists()) {
          await scratch.delete(recursive: true);
        }
      }
    });

    await check('packages', 'アプリのインストール状態', () async {
      for (final app in repository.apps) {
        final dir = repository.currentDir(app.id);
        final manifestFile = File(p.join(dir.path, 'manifest.json'));
        final page = File(p.join(dir.path, 'index.html'));
        if (!await manifestFile.exists() || !await page.exists()) {
          throw FormatException('必要ファイルがありません: ${app.id}');
        }
        final actual = ChappyPackage.parse(await manifestFile.readAsString());
        if (actual.id != app.id || actual.version != app.version) {
          throw FormatException('アプリ一覧との不一致: ${app.id}');
        }
      }
      return '${repository.apps.length} 個のアプリを確認';
    });

    await check('loopback', 'ローカルWebサーバー', () async {
      final dir = await Directory(p.join(
        repository.stagingRoot.path,
        'self_check_server',
      )).create(recursive: true);
      final file = File(p.join(dir.path, 'index.html'));
      await file.writeAsString('<html><head></head><body>Chappy test</body></html>');
      final server = LocalAppServer(dir);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      try {
        await server.start();
        final request = await client.getUrl(server.url);
        final response = await request.close().timeout(const Duration(seconds: 5));
        final html = await utf8.decoder.bind(response).join().timeout(
          const Duration(seconds: 5),
        );
        final csp = response.headers.value('content-security-policy') ?? '';
        if (response.statusCode != 200 ||
            !html.contains('/__chappy_boot.js') ||
            !csp.contains("connect-src 'none'")) {
          throw StateError('HTTP応答またはJavaScript保護設定が不正');
        }
        return '127.0.0.1でHTTP 200・CSP確認OK';
      } finally {
        client.close(force: true);
        await server.close();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    await check('diagnostics', '診断ログの保存', () async {
      final marker = 'selfcheck-${DateTime.now().microsecondsSinceEpoch}';
      await logs.add('player', 'info', 'self-check', marker);
      final logFile = File(p.join(
        repository.root.parent.path, 'chappy_diagnostics.jsonl',
      ));
      if (!await logFile.exists()) {
        throw StateError('診断ログがファイルに保存されていません');
      }
      final contents = await logFile.readAsString();
      if (!contents.contains(marker)) {
        throw StateError('書き込み済みの診断ログを再読込できません');
      }
      return '端末内のログファイルを再読込できました';
    });

    await logs.add('player', results.every((item) => item.passed) ? 'info' : 'warning',
        'self-check',
        'Self-check completed: ${results.where((item) => item.passed).length}/${results.length} passed');

    return results;
  }

  static String report(List<SelfCheckResult> results) {
    final passed = results.where((item) => item.passed).length;
    final lines = [
      'Chappy Player device self-check',
      'UTC: ${DateTime.now().toUtc().toIso8601String()}',
      'OS: ${Platform.operatingSystem}',
      'OS version: ${Platform.operatingSystemVersion}',
      'Results: $passed/${results.length} passed',
      'No data was uploaded.',
      '',
      for (final item in results)
        '[${item.passed ? 'PASS' : 'FAIL'}] ${item.id} - ${item.label} '
            '(${item.elapsedMs}ms): ${item.detail}',
    ];
    return lines.join('\n');
  }
}
