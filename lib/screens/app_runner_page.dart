import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/local_app_server.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/media_permission_policy.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/core/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _AppRunnerPageState extends State<AppRunnerPage> with WidgetsBindingObserver {
  static const MethodChannel _mediaChannel =
      MethodChannel('dev.chappy.player/media_permissions');
  bool _mediaPermissionPending = false;
  bool _nativeMicPending = false;
  bool _nativeMicActive = false;
  bool _videoStartPending = false;
  bool _nativeVideoActive = false;
  bool _videoDark = false;
  double _darkHorizontalDrag = 0;

  // Armed only after the user explicitly enters dark recording mode.
  bool _darkSessionArmed = false;
  bool _volumeStartPending = false;
  bool _volumeStopPending = false;
  bool _darkPollBusy = false;
  Map<String, dynamic>? _lastVideoOptions;
  Timer? _darkVideoPollTimer;
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
    WidgetsBinding.instance.addObserver(this);
    _startTime = Stopwatch()..start();
    _mediaChannel.setMethodCallHandler(_handleNativeVideoShortcut);
    unawaited(_initialize());
  }

  // OS volume buttons are intercepted by MainActivity only when dark mode is
  // active in the foreground. The first consent covers only this active dark session.
  Future<dynamic> _handleNativeVideoShortcut(MethodCall call) async {
    if (call.method != 'videoVolumeShortcut' || !_videoDark ||
        !_darkSessionArmed || !mounted ||
        ModalRoute.of(context)?.isCurrent != true) { return null; }
    if (call.arguments == 'stop' && _nativeVideoActive &&
        !_volumeStopPending && !_videoStartPending) {
      _volumeStopPending = true;
      try {
        await _stopNativeVideo();
      } catch (error) {
        unawaited(widget.logs.add(widget.app.id, 'error', 'volume-video-stop',
            'Video stop failed: $error'));
      } finally {
        _volumeStopPending = false;
      }
    } else if (call.arguments == 'start' && !_nativeVideoActive &&
        !_volumeStartPending && !_videoStartPending &&
        _lastVideoOptions != null) {
      _volumeStartPending = true;
      try {
        // Reuse the explicit consent from this STILL-FOREGROUND dark session.
        // Never expose the UI or open a fresh host dialog for volume-up.
        await _startNativeVideo(Map<String, dynamic>.from(_lastVideoOptions!),
            reuseDarkSessionConsent: true);
        try {
          await _controller?.runJavaScript(
              'window.dispatchEvent(new Event("chappy-native-video-started"));');
        } catch (_) {}
      } catch (error) {
        unawaited(widget.logs.add(widget.app.id, 'warning', 'volume-video-start',
            'Video restart cancelled or failed: $error'));
      } finally {
        _volumeStartPending = false;
      }
    }
    return null;
  }

  /// Each WebView request requires a manifest declaration, explicit in-app
  /// confirmation, and Android runtime permission. No silent auto-grants.
  Future<void> _handleMediaPermission(WebViewPermissionRequest request) async {
    final requested = <String>[];
    for (final type in request.types) {
      if (type == WebViewPermissionResourceType.camera) {
        requested.add('camera');
      } else if (type == WebViewPermissionResourceType.microphone) {
        requested.add('microphone');
      } else {
        await _denyMedia(request, 'unsupported WebView resource');
        return;
      }
    }
    if (!mounted || _mediaPermissionPending || _nativeVideoActive ||
        _videoStartPending ||
        ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, requested)) {
      await _denyMedia(request, 'not declared, no foreground route, or busy');
      return;
    }
    _mediaPermissionPending = true;
    final names = requested.map((e) => e == 'camera' ? 'カメラ' : 'マイク').join('・');
    try {
      unawaited(widget.logs.add(widget.app.id, 'info', 'media-permission',
          'Requested $requested'));
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: Text('$names の使用許可'),
          content: Text('ミニアプリ「${widget.app.name}」が $names を使おうとしています。'
              '使用中の映像・音声はこのミニアプリ内で処理されます。'
              '信頼できるアプリにだけ許可してください。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('拒否')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('今回だけ許可')),
          ],
        ),
      );
      if (approved != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        await _denyMedia(request, 'user denied or page closed');
        return;
      }
      final osGranted = await _mediaChannel.invokeMethod<bool>(
        'requestMediaPermissions', {'types': requested},
      );
      if (osGranted != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        await _denyMedia(request, 'Android denied or page closed');
        return;
      }
      await request.grant();
      await widget.logs.add(widget.app.id, 'info', 'media-permission',
          'Granted $requested for this WebView request');
    } catch (error) {
      await _denyMedia(request, 'permission request failed: $error');
    } finally {
      _mediaPermissionPending = false;
    }
  }

  Future<void> _denyMedia(WebViewPermissionRequest request, String reason) async {
    try {
      await request.deny();
    } catch (_) {
      // Android WebView may have already cancelled a pending request.
    }
    await widget.logs.add(widget.app.id, 'warning', 'media-permission',
        'Denied: $reason');
  }

  /// Native capture is stopped even when a mini-app JS handler is suspended.
  /// A second Android-side onPause guard exists in MainActivity.
  Future<void> _stopMedia() async {
    _darkVideoPollTimer?.cancel();
    _darkVideoPollTimer = null;
    _darkSessionArmed = false;
    _lastVideoOptions = null;
    _nativeMicActive = false;
    _nativeVideoActive = false;
    if (_videoDark && mounted) {
      setState(() => _videoDark = false);
    } else {
      _videoDark = false;
    }
    try {
      await _mediaChannel.invokeMethod<bool>('stopNativeMic');
      await _mediaChannel.invokeMethod<dynamic>('stopNativeVideo');
      await _mediaChannel.invokeMethod<bool>(
          'setVideoDark', {'enabled': false});
    } catch (_) {
      // Native host may already have gone away. Android onPause also stops.
    }
    // Never leave immersive bars hidden if the mini-app exits or backgrounds.
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript(
          'if (typeof window.__chappyStopMedia === "function") '
          'window.__chappyStopMedia();');
    } catch (_) {
      // WebView may already be disposed.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_stopMedia());
    }
  }

  /// Native AudioRecord is available only to a foreground mini-app that
  /// declares microphone permission, after user and Android consent.
  Future<Map<String, dynamic>> _startNativeMic() async {
    if (!mounted || _nativeMicPending || _nativeMicActive ||
        _nativeVideoActive || _videoStartPending ||
        ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, ['microphone'])) {
      throw StateError('Native microphone not permitted or already active');
    }
    _nativeMicPending = true;
    try {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('ネイティブマイクの使用許可'),
          content: Text('ミニアプリ「${widget.app.name}」がAndroidのマイクを直接使用して、'
              '音量と波形を表示しようとしています。音声は保存・送信しません。'
              'アプリを離れると録音を停止します。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('拒否')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('今回だけ許可')),
          ],
        ),
      );
      if (approved != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Native microphone request cancelled');
      }
      final osGranted = await _mediaChannel.invokeMethod<bool>(
        'requestMediaPermissions', {'types': ['microphone']},
      );
      if (osGranted != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Android microphone permission unavailable');
      }
      final result = await _mediaChannel.invokeMapMethod<String, dynamic>(
          'startNativeMic');
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        await _mediaChannel.invokeMethod<bool>('stopNativeMic');
        throw StateError('Native microphone page no longer foreground');
      }
      if (result == null || result['running'] != true) {
        throw StateError('Native microphone could not start');
      }
      _nativeMicActive = true;
      unawaited(widget.logs.add(widget.app.id, 'info', 'native-microphone',
          'Android AudioRecord started (waveform envelope only)'));
      return Map<String, dynamic>.from(result);
    } finally {
      _nativeMicPending = false;
    }
  }

  Future<Map<String, dynamic>> _nativeMicLevels() async {
    if (!_nativeMicActive || !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return {'running': false, 'rms': 0.0, 'levels': <double>[]};
    }
    final levels = await _mediaChannel.invokeMapMethod<String, dynamic>(
        'readNativeMic');
    if (levels == null || levels['running'] != true) {
      _nativeMicActive = false;
      return {'running': false, 'rms': 0.0, 'levels': <double>[]};
    }
    return Map<String, dynamic>.from(levels);
  }

  Future<bool> _stopNativeMic() async {
    final wasActive = _nativeMicActive;
    _nativeMicActive = false;
    try {
      await _mediaChannel.invokeMethod<bool>('stopNativeMic');
    } finally {
      if (wasActive) {
        unawaited(widget.logs.add(widget.app.id, 'info',
            'native-microphone', 'Android AudioRecord stopped'));
      }
    }
    return true;
  }

  /// The initial capture requires a user-facing confirmation. Only foreground
  /// hardware volume-up from the already approved dark session can reuse it,
  /// with the exact same camera/audio/storage options and Android permissions.
  Future<Map<String, dynamic>> _startNativeVideo(
      Map<String, dynamic> options, {bool reuseDarkSessionConsent = false}) async {
    final audio = options['audio'] == true;
    final needed = <String>['camera', if (audio) 'microphone'];
    if (!mounted || _videoStartPending || _nativeVideoActive ||
        _nativeMicPending ||
        ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, needed)) {
      throw StateError('Video camera not permitted or already recording');
    }
    final lens = options['lens'];
    final quality = options['quality'];
    final storage = options['storage'];
    if ((lens != 'back' && lens != 'front') ||
        (quality != '720' && quality != '1080') ||
        (storage != 'private' && storage != 'gallery')) {
      throw const FormatException('Invalid native video recording options');
    }
    final previous = _lastVideoOptions;
    final canReuseDarkConsent = reuseDarkSessionConsent &&
        _darkSessionArmed && _videoDark && previous != null &&
        previous['lens'] == lens && previous['quality'] == quality &&
        previous['storage'] == storage && previous['audio'] == audio;
    if (reuseDarkSessionConsent && !canReuseDarkConsent) {
      throw StateError('Dark camera session approval expired or settings changed');
    }
    _videoStartPending = true;
    try {
      if (!canReuseDarkConsent) {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('カメラ動画の録画'),
          content: Text('ミニアプリ「${widget.app.name}」がカメラで動画を録画します。'
              '${audio ? '音声も録音します。' : '音声は録音しません。'}'
              '${storage == 'private' ? '動画はChappy Playerの非公開領域に保存します。'
                  'アンインストールすると動画は消えます。' : '動画はギャラリーに公開保存します。'}'
              'この段階ではアプリを離れると録画を停止します。録画中はAndroidの'
              'カメラ使用表示が有効になります。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('今回の録画を許可')),
          ],
        ),
      );
      if (approved != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Video permission prompt cancelled');
      }
      }
      // Android runtime permission is checked on EVERY capture, even when the
      // one-session user confirmation is reused (revoked permissions fail).
      final osGranted = await _mediaChannel.invokeMethod<bool>(
          'requestMediaPermissions', {'types': needed});
      if (osGranted != true || !mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Android camera or microphone permission unavailable');
      }
      // Release WebView camera tracks before binding CameraX to the same sensor.
      try {
        await _controller?.runJavaScript(
            'if (typeof window.__chappyStopMedia === "function") '
            'window.__chappyStopMedia();');
      } catch (_) {}
      await _mediaChannel.invokeMethod<bool>('stopNativeMic');
      final result = await _mediaChannel.invokeMapMethod<String, dynamic>(
        'startNativeVideo', {
          'owner': widget.app.id, 'lens': lens, 'quality': quality,
          'audio': audio, 'storage': storage,
        });
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        await _mediaChannel.invokeMethod<dynamic>('stopNativeVideo');
        throw StateError('Camera page no longer foreground');
      }
      if (result == null ||
          (result['state'] != 'starting' && result['state'] != 'recording')) {
        throw StateError('CameraX video recorder did not start');
      }
      if (mounted) setState(() => _nativeVideoActive = true);
      _lastVideoOptions = Map<String, dynamic>.from(options);
      unawaited(widget.logs.add(widget.app.id, 'info', 'native-video',
          'CameraX foreground recording initiated; storage=$storage audio=$audio'));
      return Map<String, dynamic>.from(result);
    } finally {
      _videoStartPending = false;
    }
  }

  Future<Map<String, dynamic>> _nativeVideoStatus() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return {'state': 'idle', 'error': 'page-not-visible'};
    }
    final data = await _mediaChannel.invokeMapMethod<String, dynamic>(
        'readNativeVideo');
    final current = Map<String, dynamic>.from(data ?? {'state': 'idle'});
    // Keep the red dot until the MP4 has actually finalized; then turn green.
    if (current['state'] == 'idle' && _nativeVideoActive) {
      if (mounted) setState(() => _nativeVideoActive = false);
    } else if ((current['state'] == 'recording' ||
        current['state'] == 'starting') && !_nativeVideoActive) {
      if (mounted) setState(() => _nativeVideoActive = true);
    }
    return current;
  }

  Future<Map<String, dynamic>> _stopNativeVideo() async {
    // Native CameraX finalization is asynchronous. Dark mode stays active,
    // and the dot only turns green after status reaches idle.
    final data = await _mediaChannel.invokeMapMethod<String, dynamic>(
        'stopNativeVideo');
    return Map<String, dynamic>.from(data ?? {'state': 'idle'});
  }

  Future<bool> _setVideoDark(bool enabled) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true ||
        (enabled && !_nativeVideoActive && !_darkSessionArmed)) {
      throw StateError('Cannot change recording display outside approved camera session');
    }
    final applied = await _mediaChannel.invokeMethod<bool>(
        'setVideoDark', {'enabled': enabled});
    final nowDark = enabled && applied == true;
    if (nowDark) _darkSessionArmed = true;
    if (!enabled) _darkSessionArmed = false;
    // Immersive sticky hides status/navigation bars, revealing them temporarily
    // on system edge swipes. Android retains control of camera/mic indicators.
    try {
      await SystemChrome.setEnabledSystemUIMode(
          nowDark ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    } catch (error) {
      unawaited(widget.logs.add(widget.app.id, 'warning', 'video-immersive',
          'Failed to change system bar mode: $error'));
    }
    if (mounted) setState(() => _videoDark = nowDark);
    _darkVideoPollTimer?.cancel();
    _darkVideoPollTimer = null;
    if (nowDark) {
      _darkVideoPollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (_darkPollBusy || !mounted) return;
        _darkPollBusy = true;
        unawaited(_nativeVideoStatus().catchError((Object _) => <String, dynamic>{})
            .whenComplete(() { _darkPollBusy = false; }));
      });
    }
    return _videoDark;
  }

  /// Disk statistics for the app's private MP4 storage volume; no paths.
  Future<Map<String, dynamic>> _videoStorageInfo() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, ['camera'])) {
      throw StateError('Video storage information unavailable');
    }
    final info = await _mediaChannel.invokeMapMethod<String, dynamic>(
        'readVideoStorage', {'owner': widget.app.id});
    if (info == null || info['totalBytes'] is! num ||
        info['availableBytes'] is! num) {
      throw const FormatException('Invalid Android storage information');
    }
    return Map<String, dynamic>.from(info);
  }

  Future<void> _setDarkSwipeBrightness(double brightness) async {
    if (!_videoDark || !mounted || !_darkSessionArmed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    try {
      final changed = await _mediaChannel.invokeMethod<bool>(
          'setVideoBrightness', {'brightness': brightness});
      if (changed != true) {
        unawaited(widget.logs.add(widget.app.id, 'warning', 'dark-brightness',
            'Dark brightness gesture was not applied'));
      }
    } catch (error) {
      unawaited(widget.logs.add(widget.app.id, 'warning', 'dark-brightness',
          'Brightness change failed: $error'));
    }
  }

  Future<List<Map<String, dynamic>>> _listPrivateVideos() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, ['camera'])) {
      throw StateError('Video library not available to this app');
    }
    final videos = await _mediaChannel.invokeListMethod<dynamic>(
        'listPrivateVideos', {'owner': widget.app.id});
    return (videos ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<bool> _openPrivateVideo(Map<String, dynamic> params) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, ['camera']) ||
        params['id'] is! String) {
      throw StateError('Video file cannot be opened');
    }
    return await _mediaChannel.invokeMethod<bool>(
        'openPrivateVideo', {'owner': widget.app.id, 'id': params['id']}) ?? false;
  }

  Future<bool> _deletePrivateVideo(Map<String, dynamic> params) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true ||
        !canRequestChappyMedia(widget.app.permissions, ['camera']) ||
        params['id'] is! String) {
      throw StateError('Video deletion not permitted');
    }
    final id = params['id'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('非公開動画を削除'),
        content: Text('$id を完全に削除しますか？元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('削除する')),
        ],
      ),
    );
    if (confirmed != true || !mounted ||
        ModalRoute.of(context)?.isCurrent != true) { return false; }
    return await _mediaChannel.invokeMethod<bool>(
        'deletePrivateVideo', {'owner': widget.app.id, 'id': id}) ?? false;
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

  Future<void> _checkBridgeHealth(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
          'Boolean(window.Chappy && window.ChappyHost && '
          'typeof window.__chappyResolve === "function")');
      final ready = result == true || result.toString() == 'true';
      await widget.logs.add(widget.app.id,
          ready ? 'info' : 'error',
          'bridge-health',
          ready ? 'JavaScript bridge initialized' : 'JavaScript bridge not initialized');
      if (!ready && mounted) {
        setState(() {
          _fatal = 'WebViewのページは表示されましたが、'
              'JavaScriptブリッジの初期化に失敗しました。診断ログを確認してください。';
          _loading = false;
        });
      }
    } catch (error) {
      await widget.logs.add(widget.app.id, 'error', 'bridge-health',
          'Failed to probe JavaScript bridge: $error');
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
      final controller = WebViewController(
        onPermissionRequest: (request) {
          unawaited(_handleMediaPermission(request));
        },
      );
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
            unawaited(_checkBridgeHealth(controller));
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
      final server = _server;
      _server = null;
      if (server != null) { await server.close(); }
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
        case 'microphone.start':
          value = await _startNativeMic();
          break;
        case 'microphone.levels':
          value = await _nativeMicLevels();
          break;
        case 'microphone.stop':
          value = await _stopNativeMic();
          break;
        case 'video.start':
          value = await _startNativeVideo(params);
          break;
        case 'video.status':
          value = await _nativeVideoStatus();
          break;
        case 'video.stop':
          value = await _stopNativeVideo();
          break;
        case 'video.dark':
          value = await _setVideoDark(params['enabled'] == true);
          break;
        case 'video.storageInfo':
          value = await _videoStorageInfo();
          break;
        case 'video.list':
          value = await _listPrivateVideos();
          break;
        case 'video.open':
          value = await _openPrivateVideo(params);
          break;
        case 'video.delete':
          value = await _deletePrivateVideo(params);
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
    WidgetsBinding.instance.removeObserver(this);
    _mediaChannel.setMethodCallHandler(null);
    _darkVideoPollTimer?.cancel();
    unawaited(_stopMedia());
    _loadWatchdog?.cancel();
    final server = _server;
    if (server != null) { unawaited(server.close()); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _videoDark ? null : AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.app.name, style: const TextStyle(fontSize: 16)),
          Text(widget.app.version, style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(
            tooltip: 'このアプリのログ',
            onPressed: () {
              unawaited(_stopMedia());
              Navigator.of(context).pushNamed('/logs', arguments: widget.app.id);
            },
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
        if (_videoDark)
          Positioned.fill(child: ColoredBox(
            color: Colors.black,
            // Visible 8px red/green LED with a larger invisible gesture zone.
            // Double tap restores the UI; horizontal right = max and
            // horizontal left = min per-window brightness while dark.
            child: SafeArea(child: Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => unawaited(_setVideoDark(false)),
                onHorizontalDragStart: (_) => _darkHorizontalDrag = 0,
                onHorizontalDragUpdate: (details) {
                  _darkHorizontalDrag += details.delta.dx;
                },
                onHorizontalDragEnd: (_) {
                  final swipe = _darkHorizontalDrag;
                  _darkHorizontalDrag = 0;
                  if (swipe >= 24) {
                    unawaited(_setDarkSwipeBrightness(1.0));
                  } else if (swipe <= -24) {
                    unawaited(_setDarkSwipeBrightness(0.01));
                  }
                },
                onHorizontalDragCancel: () => _darkHorizontalDrag = 0,
                child: SizedBox(width: 96, height: 88,
                  child: Align(alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: _nativeVideoActive ? Colors.redAccent : Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )),
          )),
      ]),
    );
  }
}
