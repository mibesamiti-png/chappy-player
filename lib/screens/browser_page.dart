import 'dart:async';

import 'package:chappy_player/core/browser_url_policy.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// R7: trusted host-only browser. NO ChappyHost JS channel or native bridge.
/// Public HTTPS navigation only; JavaScript is disabled by default.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage>
    with WidgetsBindingObserver {
  final _address = TextEditingController();
  WebViewController? _controller;
  String? _notice;
  int _generation = 0;
  bool _foreground = true;
  bool _hasPage = false;
  bool _loading = false;
  bool _back = false;
  bool _forward = false;
  bool _js = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_newController());
  }

  Future<void> _newController() async {
    final generation = ++_generation;
    try {
      final controller = WebViewController(
        onPermissionRequest: (request) => unawaited(request.deny()),
      );
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setBackgroundColor(const Color(0xFF10151F));
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url == 'about:blank') return NavigationDecision.navigate;
          if (_foreground && BrowserUrlPolicy.allowsNavigation(request.url)) {
            return NavigationDecision.navigate;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _foreground && generation == _generation) {
              setState(() => _notice = '安全上の理由で移動を拒否しました（公開HTTPSのみ）。');
            }
          });
          return NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (!mounted || !_foreground || generation != _generation ||
              !BrowserUrlPolicy.allowsNavigation(url)) {
            return;
          }
          setState(() {
            _loading = true;
            _hasPage = true;
            _address.text = url;
            _notice = null;
          });
        },
        onPageFinished: (_) {
          if (!mounted || !_foreground || generation != _generation) {
            return;
          }
          setState(() => _loading = false);
          unawaited(_refreshHistory(controller, generation));
        },
        onWebResourceError: (error) {
          if (!mounted || !_foreground || generation != _generation ||
              error.isForMainFrame == false) {
            return;
          }
          setState(() {
            _loading = false;
            _notice = '読み込みに失敗しました。URLか接続状態を確認してください。';
          });
        },
      ));
      if (!mounted || !_foreground || generation != _generation) return;
      setState(() {
        _controller = controller;
        _loading = false;
        _back = false;
        _forward = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _notice = 'ブラウザの準備に失敗しました。');
      }
    }
  }

  Future<void> _refreshHistory(WebViewController controller, int generation) async {
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (mounted && _foreground && generation == _generation) {
        setState(() {
          _back = back;
          _forward = forward;
        });
      }
    } catch (_) {
      // An already-disposed native view may reject history requests.
    }
  }

  Future<void> _navigate() async {
    final controller = _controller;
    if (controller == null || !_foreground || _loading) return;
    late final Uri uri;
    try {
      uri = BrowserUrlPolicy.fromInput(_address.text);
    } on FormatException {
      setState(() => _notice =
          '公開HTTPSのドメインを入力してください。HTTP・IPアドレス・端末内URLは不可。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _hasPage = true;
      _loading = true;
      _notice = null;
    });
    try {
      await controller.loadRequest(uri);
    } catch (_) {
      if (mounted && _foreground) {
        setState(() {
          _loading = false;
          _notice = '読み込みに失敗しました。';
        });
      }
    }
  }

  Future<void> _goBack() async {
    if (!_foreground || !_back || _controller == null) return;
    await _controller!.goBack();
    await _refreshHistory(_controller!, _generation);
  }

  Future<void> _goForward() async {
    if (!_foreground || !_forward || _controller == null) return;
    await _controller!.goForward();
    await _refreshHistory(_controller!, _generation);
  }

  Future<void> _reload() async {
    if (!_foreground || !_hasPage || _controller == null) return;
    await _controller!.reload();
  }

  Future<void> _toggleJs(bool enabled) async {
    final controller = _controller;
    final startingGeneration = _generation;
    if (!_foreground || controller == null || _js == enabled) return;
    if (enabled) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('JavaScriptを有効にする'),
          content: const Text('Webサイトのスクリプトは外部通信を行う場合があります。'
              '信頼できるサイトでのみ有効にしてください。\n'
              '端末操作・署名鍵・ChappyミニアプリAPIは一切渡しません。'
              'アプリを背景化するとOFFに戻ります。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('今回だけON')),
          ],
        ),
      );
      if (!mounted || !_foreground || approved != true ||
          startingGeneration != _generation ||
          !identical(controller, _controller)) return;
    }
    try {
      await controller.setJavaScriptMode(
        enabled ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
      if (mounted && _foreground && identical(_controller, controller)) {
        setState(() => _js = enabled);
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'JavaScript設定の変更に失敗しました。');
    }
  }

  Future<void> _clearData() async {
    final controller = _controller;
    final startingGeneration = _generation;
    if (!_foreground || controller == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('WebView閲覧データを削除'),
        content: const Text('この画面の一時履歴を終了し、WebViewキャッシュ・'
            'ローカルストレージ・Cookieを削除します。\n\n'
            'Android WebViewのCookie等は他のミニアプリと共有される場合があります。'
            'ミニアプリ内サイトからもログアウトする可能性があり、'
            '完全に独立した保存領域ではありません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('戻る')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('共有データも削除')),
        ],
      ),
    );
    if (!mounted || !_foreground || approved != true ||
        startingGeneration != _generation ||
        !identical(controller, _controller)) return;
    try {
      await controller.clearCache();
      await controller.clearLocalStorage();
      await WebViewCookieManager().clearCookies();
      if (!mounted || !_foreground) return;
      _address.clear();
      setState(() {
        _controller = null;
        _hasPage = false;
        _loading = false;
        _back = false;
        _forward = false;
        _js = false;
        _notice = '閲覧データを削除しました。URLを再入力してください。';
      });
      await _newController(); // Drops native per-view back/forward history.
    } catch (_) {
      if (mounted) setState(() => _notice = '一部のデータを削除できませんでした。');
    }
  }

  void _closeSession() {
    _foreground = false;
    ++_generation;
    final old = _controller;
    if (old != null) {
      unawaited(old.loadRequest(Uri.parse('about:blank'))
          .catchError((Object _) {}));
      unawaited(old.setJavaScriptMode(JavaScriptMode.disabled)
          .catchError((Object _) {}));
    }
    if (mounted) {
      _address.clear();
      setState(() {
        _controller = null;
        _hasPage = false;
        _loading = false;
        _back = false;
        _forward = false;
        _js = false;
        _notice = '画面を離れたため閲覧を終了。再度URLを入力してください。';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_foreground) {
        _foreground = true;
        unawaited(_newController());
      }
    } else if (_foreground) {
      _closeSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foreground = false;
    ++_generation;
    _address.dispose();
    final old = _controller;
    if (old != null) {
      unawaited(old.loadRequest(Uri.parse('about:blank'))
          .catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Chappy Browser — R7プレビュー')),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(children: [
            Expanded(child: TextField(
              key: const Key('browser_address'),
              controller: _address,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '公開HTTPSサイト',
                hintText: 'example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => unawaited(_navigate()),
            )),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('browser_go'),
              onPressed: controller == null || _loading || !_foreground
                  ? null : _navigate,
              child: const Text('移動'),
            ),
          ]),
        ),
        Row(children: [
          IconButton(
            key: const Key('browser_back'), tooltip: '戻る',
            onPressed: _back && _foreground ? _goBack : null,
            icon: const Icon(Icons.arrow_back)),
          IconButton(
            key: const Key('browser_forward'), tooltip: '進む',
            onPressed: _forward && _foreground ? _goForward : null,
            icon: const Icon(Icons.arrow_forward)),
          IconButton(
            key: const Key('browser_reload'), tooltip: '更新',
            onPressed: _hasPage && _foreground ? _reload : null,
            icon: const Icon(Icons.refresh)),
          IconButton(
            key: const Key('browser_clear'), tooltip: '閲覧データ削除',
            onPressed: controller != null && _foreground ? _clearData : null,
            icon: const Icon(Icons.delete_sweep_outlined)),
          const Spacer(),
          const Text('JS', style: TextStyle(fontSize: 13)),
          Switch(
            key: const Key('browser_javascript'),
            value: _js,
            onChanged: controller == null || !_foreground ? null : _toggleJs,
          ),
        ]),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_notice != null) Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_notice!, key: const Key('browser_status'),
              style: const TextStyle(color: Colors.orangeAccent))),
        Expanded(
          child: controller == null || !_foreground || !_hasPage
            ? const Center(child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('公開HTTPS URLを入力して移動を押してください。\n'
                    'JavaScriptは初期OFF、カメラ/マイクは常に拒否。\n'
                    '訪問URLや閲覧履歴をChappyのログに保存しません。',
                    textAlign: TextAlign.center)))
            : WebViewWidget(
                key: ValueKey<int>(_generation),
                controller: controller),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('公開HTTPSのみ。HTTP/LAN内IP/ファイル等は不可。'
              'AndroidのWebView Cookieはミニアプリと共有される場合があります。',
              style: TextStyle(fontSize: 11, color: Colors.white60)),
        ),
      ])),
    );
  }
}
