import 'dart:io';

import 'package:path/path.dart' as p;

class LocalAppServer {
  final Directory appDirectory;
  HttpServer? _server;
  LocalAppServer(this.appDirectory);

  Uri get url => Uri.parse('http://127.0.0.1:${_server!.port}/index.html');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      try {
        await _serve(request);
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'self'; connect-src 'none'; script-src 'self' 'unsafe-inline'; "
      "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
      "font-src 'self' data:; media-src 'self' data: blob:; "
      "object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'",
    );
    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    if (request.uri.path == '/__chappy_media.js') {
      response.headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
      response.write(_mediaScript);
      await response.close();
      return;
    }
    if (request.uri.path == '/__chappy_boot.js') {
      response.headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
      response.write(_bootScript);
      await response.close();
      return;
    }
    final route = request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
    if (!RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(route) ||
        route.split('/').any((part) => part == '..' || part == '.')) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    final file = File(p.join(appDirectory.path, p.joinAll(route.split('/'))));
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    const types = {
      '.html': 'text/html', '.js': 'application/javascript',
      '.mjs': 'application/javascript', '.css': 'text/css',
      '.json': 'application/json', '.svg': 'image/svg+xml',
      '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.webp': 'image/webp', '.gif': 'image/gif', '.wasm': 'application/wasm',
      '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg', '.wav': 'audio/wav',
    };
    final mime = types[p.extension(file.path).toLowerCase()] ??
        'application/octet-stream';
    // HttpResponse.write() uses Latin-1 if a Content-Type lacks charset.
    // Our HTML includes Japanese characters; use UTF-8 to avoid HTTP 500.
    final textual = mime.startsWith('text/') ||
        mime == 'application/javascript' ||
        mime == 'application/json' ||
        mime == 'image/svg+xml';
    response.headers.set('Content-Type',
        textual ? '$mime; charset=utf-8' : mime);
    if (p.basename(file.path) == 'index.html') {
      var html = await file.readAsString();
      const bootstrap = '<script src="/__chappy_media.js"></script>'
          '<script src="/__chappy_boot.js"></script>';
      final headTag = RegExp(r'<head[^>]*>', caseSensitive: false);
      final match = headTag.firstMatch(html);
      if (match != null) {
        html = html.replaceRange(match.end, match.end, bootstrap);
      } else {
        html = '$bootstrap$html';
      }
      response.write(html);
    } else {
      await response.addStream(file.openRead());
    }
    await response.close();
  }
}


const _mediaScript = r'''
(function () {
  'use strict';
  // Track only streams opened by this page. There is no native capture bridge:
  // navigator.mediaDevices.getUserMedia still uses Android + WebView consent.
  const streams = new Set();
  const devices = navigator.mediaDevices;
  function stopMedia() {
    streams.forEach(stream => {
      try { stream.getTracks().forEach(track => track.stop()); } catch (_) {}
    });
    streams.clear();
  }
  Object.defineProperty(window, '__chappyStopMedia', {
    configurable: false, writable: false, value: stopMedia
  });
  window.addEventListener('pagehide', stopMedia);
  if (!devices || typeof devices.getUserMedia !== 'function') return;
  const original = devices.getUserMedia.bind(devices);
  try {
    devices.getUserMedia = async function (constraints) {
      const stream = await original(constraints);
      streams.add(stream);
      stream.getTracks().forEach(track => {
        track.addEventListener('ended', () => {
          if (stream.getTracks().every(item => item.readyState === 'ended')) {
            streams.delete(stream);
          }
        });
      });
      return stream;
    };
  } catch (_) {
    // Android WebView may disallow overriding this method. The host will
    // additionally release its WebView when leaving the page.
  }
})();
''';

const _bootScript = r'''
(function () {
  'use strict';
  let seq = 0;
  const pending = new Map();
  const timeoutMs = 12000;
  window.__chappyResolve = function (msg) {
    const item = pending.get(msg.requestId);
    if (!item) return;
    pending.delete(msg.requestId);
    clearTimeout(item.timer);
    if (msg.ok) item.resolve(msg.value);
    else item.reject(new Error(String(msg.error || 'unknown error')));
  };
  function call(method, params) {
    return new Promise((resolve, reject) => {
      const requestId = String(++seq);
      // Native microphone asks the user in two successive permission dialogs.
      // Do not time out while the user is deciding: Android/Flutter will
      // reject a cancelled request and always stop capture on background.
      const timer = (method === 'microphone.start' || method === 'video.start' ||
                     method === 'video.delete')
        ? null : setTimeout(() => {
        pending.delete(requestId);
        reject(new Error('Chappy API timeout'));
      }, timeoutMs);
      pending.set(requestId, {resolve, reject, timer});
      window.ChappyHost.postMessage(JSON.stringify({requestId, method, params}));
    });
  }
  Object.defineProperty(window, 'Chappy', {
    configurable: false, writable: false,
    value: Object.freeze({
      storage: Object.freeze({
        get: key => call('storage.get', {key}),
        set: (key, value) => call('storage.set', {key, value}),
        remove: key => call('storage.remove', {key})
      }),
      info: () => call('info.get', {}),
      microphone: Object.freeze({
        start: () => call('microphone.start', {}),
        levels: () => call('microphone.levels', {}),
        stop: () => call('microphone.stop', {})
      }),
      video: Object.freeze({
        start: (options) => call('video.start', options || {}),
        status: () => call('video.status', {}),
        storageInfo: () => call('video.storageInfo', {}),
        stop: () => call('video.stop', {}),
        dark: (enabled) => call('video.dark', {enabled: enabled === true}),
        list: () => call('video.list', {}),
        open: (id) => call('video.open', {id: String(id)}),
        delete: (id) => call('video.delete', {id: String(id)})
      }),
      log: (message) => call('log', {message: String(message)})
    })
  });
  window.addEventListener('error', event => {
    try { window.ChappyHost.postMessage(JSON.stringify({
      requestId: '', method: 'diagnostic.error',
      params: {message: String(event.message), stack: String(event.error?.stack || '')}
    })); } catch (_) {}
  });
  window.addEventListener('unhandledrejection', event => {
    try { window.ChappyHost.postMessage(JSON.stringify({
      requestId: '', method: 'diagnostic.rejection',
      params: {message: String(event.reason?.stack || event.reason || 'unknown')}
    })); } catch (_) {}
  });
})();
''';
