import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/local_app_server.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/core/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppRunnerPage extends StatefulWidget {
  final ChappyPackage app;
  final PackageRepository repository;
  final LogStore logs;

  const AppRunnerPage({
    super.key,
    required this.app,
    required this.repository,
    required this.logs,
  });

  @override
  State<AppRunnerPage> createState() => _AppRunnerPageState();
}

class _AppRunnerPageState extends State<AppRunnerPage> {
  LocalAppServer? _server;
  WebViewController? _controller;
  String? _fatal;
  bool _loading = true;
  Timer? _loadWatchdog;
  int _loadProgress = 0;
  late final StorageService _storage = StorageService(widget.repository.dataRoot);
  late final Stopwatch _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = Stopwatch()..start();
    unawaited(_initialize());
  }

  void _armWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_loading || _fatal != null) { return; }
      const detail = 'ミニアプリの読み込みが20秒以内に終わりませんでした。'
          '端末セルフチェックと診断ログを確認してください。';
      setState(() {
        _fatal = detail;
        _loading = false;
      });
      unawaited(widget.logs.add(widget.app.id, 'error', 'webview-timeout',
          '$detail (last progress: $_loadProgress%)'));
    });
  }

  Future<void> _preflight(LocalAppServer server) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(server.url)
          .timeout(const Duration(seconds: 5));
      final response = await request.close()
          .timeout(const Duration(seconds: 5));
      final html = await utf8.decoder.bind(response).join()
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok ||
          !html.contains('/__chappy_boot.js')) {
        throw StateError('ローカルサーバーの応答が不正です'
            ' (HTTP ${response.statusCode})');
      }
      await widget.logs.add(widget.app.id, 'info', 'server',
          'Loopback preflight OK (HTTP 200, injected bridge script)');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _retry() async {
    if (!mounted) { return; }
    _loadWatchdog?.cancel();
    setState(() {
      _fatal = null;
      _loading = true;
      _loadProgress = 0;
    });
    try {
      final server = _server;
      final controller = _controller;
      if (server == null || controller == null) {
        await _initialize();
      } else {
        await _preflight(server);
        _armWatchdog();
        await controller.loadRequest(server.url);
      }
    } catch (error, stack) {
      await widget.logs.add(widget.app.id, 'error', 'runner-retry', '$error\n$stack');
      if (mounted) {
        _loadWatchdog?.cancel();
        setState(() {
          _fatal = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _initialize() async {
    try {
      final server = LocalAppServer(widget.repository.currentDir(widget.app.id));
      await server.start();
      if (!mounted) {
        await server.close();
        return;
      }
      _server = server;
      await _preflight(server);
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(const Color(0xFF111827));
      await controller.addJavaScriptChannel(
        'ChappyHost',
        onMessageReceived: (msg) => unawaited(_handleMessage(msg.message)),
      );
      await controller.setOnConsoleMessage((message) {
        unawaited(widget.logs.add(
          widget.app.id,
          message.level.toString(),
          'console',
          message.message,
        ));
      });
      await controller.setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted && _loading) {
            setState(() => _loadProgress = progress);
          }
        },
        onPageStarted: (_) {
          unawaited(widget.logs.add(widget.app.id, 'info', 'webview',
              'Main page navigation started'));
        },
        onNavigationRequest: (request) {
          // Strictly prevent top-level navigation away from this mini-app.
          final target = Uri.tryParse(request.url);
          final allowed = target != null &&
              target.scheme == server.url.scheme &&
              target.host == server.url.host &&
              target.port == server.url.port;
          if (!allowed) {
            unawaited(widget.logs.add(widget.app.id, 'warning',
                'navigation', 'Blocked navigation to external origin'));
          }
          return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          final mainFrame = error.isForMainFrame != false;
          final detail = 'WebView error ${error.errorCode}: ${error.description}';
          unawaited(widget.logs.add(widget.app.id, 'error',
              mainFrame ? 'webview-main-frame' : 'webview-resource', detail));
          if (mainFrame && mounted) {
            _loadWatchdog?.cancel();
            setState(() {
              _fatal = detail;
              _loading = false;
            });
          }
        },
        onPageFinished: (_) {
          _loadWatchdog?.cancel();
          if (mounted && _fatal == null) {
            setState(() {
              _loading = false;
              _loadProgress = 100;
            });
            unawaited(widget.logs.add(widget.app.id, 'info', 'performance',
                'First page loaded in ${_startTime.elapsedMilliseconds} ms'));
          }
        },
      ));
      if (!mounted) { return; }
      setState(() => _controller = controller);
      _armWatchdog();
      await controller.loadRequest(server.url);
      await widget.logs.add(widget.app.id, 'info', 'runner', 'Started ${widget.app.version}');
    } catch (error, stack) {
      _loadWatchdog?.cancel();
      await widget.logs.add(widget.app.id, 'error', 'runner', '$error\n$stack');
      if (mounted) {
        setState(() {
          _fatal = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleMessage(String input) async {
    if (input.length > 256 * 1024) {
      await widget.logs.add(widget.app.id, 'warning', 'bridge', 'Message too large');
      return;
    }
    String requestId = '';
    try {
      final message = jsonDecode(input) as Map<String, dynamic>;
      requestId = message['requestId'] is String ? message['requestId'] as String : '';
      final method = message['method'];
      final params = message['params'];
      if (method is! String || params is! Map<String, dynamic>) {
        throw const FormatException('Invalid bridge message');
      }
      dynamic value;
      switch (method) {
        case 'storage.get':
          value = await _storage.get(widget.app.id, _key(params));
          break;
        case 'storage.set':
          await _storage.set(widget.app.id, _key(params), params['value']);
          value = true;
          break;
        case 'storage.remove':
          await _storage.remove(widget.app.id, _key(params));
          value = true;
          break;
        case 'info.get':
          value = {'id': widget.app.id, 'version': widget.app.version, 'player': '0.1.0'};
          break;
        case 'log':
          final text = params['message'];
          if (text is! String) { throw const FormatException('message must be text'); }
          await widget.logs.add(widget.app.id, 'info', 'miniapp', text);
          value = true;
          break;
        case 'diagnostic.error':
        case 'diagnostic.rejection':
          await widget.logs.add(widget.app.id, 'error', method,
              '${params['message'] ?? ''}\n${params['stack'] ?? ''}');
          return;
        default:
          throw FormatException('Unsupported API: $method');
      }
      if (requestId.isNotEmpty) { await _respond(requestId, ok: true, value: value); }
    } catch (error) {
      await widget.logs.add(widget.app.id, 'error', 'bridge', '$error');
      if (requestId.isNotEmpty) { await _respond(requestId, ok: false, error: '$error'); }
    }
  }

  String _key(Map<String, dynamic> params) {
    final key = params['key'];
    if (key is! String || key.isEmpty || key.length > 100) {
      throw const FormatException('Invalid storage key');
    }
    return key;
  }

  Future<void> _respond(String requestId, {required bool ok, dynamic value, String? error}) async {
    final controller = _controller;
    if (controller == null || !mounted) { return; }
    final payload = jsonEncode({
      'requestId': requestId,
      'ok': ok,
      if (ok) 'value': value else 'error': error,
    });
    try {
      await controller.runJavaScript('window.__chappyResolve($payload);');
    } catch (_) {
      // Page may already be closing.
    }
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    final server = _server;
    if (server != null) { unawaited(server.close()); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.app.name, style: const TextStyle(fontSize: 16)),
          Text(widget.app.version, style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(
            tooltip: 'このアプリのログ',
            onPressed: () => Navigator.of(context).pushNamed('/logs', arguments: widget.app.id),
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: Stack(children: [
        if (_controller != null)
          Positioned.fill(child: WebViewWidget(controller: _controller!)),
        if (_fatal != null)
          Positioned.fill(child: ColoredBox(
            color: const Color(0xFF111827),
            child: Center(child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 44, color: Colors.orangeAccent),
                const SizedBox(height: 12),
                const Text('ミニアプリの起動に失敗しました',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SelectableText(_fatal!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('もう一度読み込む'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(
                    '/logs', arguments: widget.app.id),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('このアプリの診断ログを開く'),
                ),
              ]),
            )),
          )),
        if (_loading && _fatal == null)
          Positioned.fill(child: ColoredBox(
            color: const Color(0xFF111827),
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('読み込み中… $_loadProgress%'),
              ],
            )),
          )),
      ]),
    );
  }
}
