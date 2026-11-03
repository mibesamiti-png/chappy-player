import 'dart:async';
import 'dart:convert';

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
  late final StorageService _storage = StorageService(widget.repository.dataRoot);
  late final Stopwatch _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = Stopwatch()..start();
    unawaited(_initialize());
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
          unawaited(widget.logs.add(widget.app.id, 'error', 'webview',
              '${error.errorCode}: ${error.description}'));
        },
        onPageFinished: (_) {
          if (mounted) {
            setState(() => _loading = false);
            unawaited(widget.logs.add(widget.app.id, 'info', 'performance',
                'First page loaded in ${_startTime.elapsedMilliseconds} ms'));
          }
        },
      ));
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(server.url);
      await widget.logs.add(widget.app.id, 'info', 'runner', 'Started ${widget.app.version}');
    } catch (error, stack) {
      await widget.logs.add(widget.app.id, 'error', 'runner', '$error\n$stack');
      if (mounted) setState(() { _fatal = error.toString(); _loading = false; });
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
          if (text is! String) throw const FormatException('message must be text');
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
      if (requestId.isNotEmpty) await _respond(requestId, ok: true, value: value);
    } catch (error) {
      await widget.logs.add(widget.app.id, 'error', 'bridge', '$error');
      if (requestId.isNotEmpty) await _respond(requestId, ok: false, error: '$error');
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
    if (controller == null || !mounted) return;
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
    final server = _server;
    if (server != null) unawaited(server.close());
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
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_fatal != null) Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('起動失敗: $_fatal'),
        )),
        if (_loading) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}
