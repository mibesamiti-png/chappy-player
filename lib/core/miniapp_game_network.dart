import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Public TLS-only URL policy. The host approves each origin separately.
class GameNetworkPolicy {
  static const maxMessageBytes = 8192;
  static const maxResponseBytes = 65536;
  static const maxQueuedMessages = 64;

  static Uri validate(String text, {required bool websocket}) {
    if (text.length > 1500) throw const FormatException('Network URL too long');
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != (websocket ? 'wss' : 'https') ||
        uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty ||
        uri.path.length > 720 || uri.query.length > 512 ||
        !({443, 8443, 9443}.contains(uri.hasPort ? uri.port : 443))) {
      throw const FormatException('Use HTTPS/WSS on 443, 8443 or 9443');
    }
    final host = uri.host.toLowerCase();
    if (host.length > 253 || !host.contains('.') ||
        host.endsWith('.local') || host.endsWith('.localhost') ||
        host.endsWith('.internal') || host.endsWith('.test') ||
        host.endsWith('.invalid') ||
        InternetAddress.tryParse(host) != null ||
        host.split('.').any((part) =>
            !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
                .hasMatch(part))) {
      throw const FormatException('A public DNS name is required');
    }
    return uri;
  }

  static String origin(Uri uri) =>
      '${uri.scheme}://${uri.host}:${uri.hasPort ? uri.port : 443}';

  static bool isPublicAddress(InternetAddress ip) {
    final a = ip.rawAddress;
    if (a.length == 16) {
      // 2000::/3 contains reserved and documentation prefixes too.
      // Reject them rather than treating every global-unicast-shaped IP
      // as safe for an app-controlled outbound connection.
      if (a[0] < 0x20 || a[0] > 0x3f) return false;
      if (a[0] == 0x20 && a[1] == 0x01 &&
          (a[2] <= 0x01 || (a[2] == 0x0d && a[3] == 0xb8))) {
        return false; // 2001::/23 special-purpose; 2001:db8::/32 docs.
      }
      if (a[0] == 0x20 && a[1] == 0x02) return false; // 2002::/16 6to4.
      if (a[0] == 0x3f && a[1] == 0xff && (a[2] & 0xf0) == 0) {
        return false; // 3fff::/20 documentation.
      }
      return true;
    }
    if (a.length != 4) return false;
    final x = a[0], y = a[1], z = a[2];
    return !(x == 0 || x == 10 || x == 127 || x >= 224 ||
        x == 169 && y == 254 ||
        x == 172 && y >= 16 && y <= 31 ||
        x == 192 && y == 168 ||
        x == 100 && y >= 64 && y <= 127 ||
        x == 198 && (y == 18 || y == 19) ||
        x == 192 && y == 0 || // 192.0.0.0/24 protocol assignments.
        x == 192 && y == 88 && z == 99 || // Deprecated 6to4 relay.
        x == 192 && y == 0 && z == 2 ||
        x == 198 && y == 51 && z == 100 ||
        x == 203 && y == 0 && z == 113);
  }

  static Future<InternetAddress> resolvePublic(String host,
      {Future<List<InternetAddress>> Function(String)? lookup}) async {
    final addresses = await (lookup ?? InternetAddress.lookup)(host)
        .timeout(const Duration(seconds: 4));
    if (addresses.isEmpty || addresses.any((ip) => !isPublicAddress(ip))) {
      throw const FormatException('Private/reserved server address blocked');
    }
    return addresses.firstWhere(
      (ip) => ip.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
  }
}

/// One bounded transport instance per AppRunnerPage. Never transfers binary
/// assets or grants the WebView network access.
class MiniAppGameNetwork {
  bool _foreground = true;
  int _epoch = 0;
  bool _connecting = false;
  WebSocket? _socket;
  HttpClient? _webSocketClient;
  StreamSubscription<dynamic>? _listener;
  final Set<HttpClient> _httpRequests = <HttpClient>{};
  final Queue<String> _queue = Queue<String>();
  int _dropped = 0;
  int _lastSendMs = 0;

  bool get connected =>
      _foreground && _socket?.readyState == WebSocket.open;

  void resume() { _foreground = true; }

  void pause() {
    _foreground = false;
    _epoch++;
    for (final client in _httpRequests) { client.close(force: true); }
    _httpRequests.clear();
    close();
  }

  void _active(int epoch) {
    if (!_foreground || epoch != _epoch) {
      throw StateError('Network stopped when mini-app left foreground');
    }
  }

  HttpClient _client(Uri uri, InternetAddress address) {
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    client.connectionFactory = (url, proxy, proxyPort) {
      if (proxy != null || proxyPort != null ||
          url.host != uri.host ||
          url.port != (uri.hasPort ? uri.port : 443)) {
        throw StateError('Proxy or different destination blocked');
      }
      // Connect to the already-vetted IP, no second DNS lookup or redirect.
      // Dart still verifies TLS for the requested DNS hostname.
      return Socket.startConnect(address, uri.hasPort ? uri.port : 443);
    };
    return client;
  }

  Future<Map<String, dynamic>> request(
      Uri uri, String method, String body) async {
    if (method != 'GET' && method != 'POST' ||
        method == 'GET' && body.isNotEmpty ||
        utf8.encode(body).length > GameNetworkPolicy.maxMessageBytes) {
      throw const FormatException('Only bounded GET/POST text is allowed');
    }
    final epoch = _epoch;
    _active(epoch);
    final address = await GameNetworkPolicy.resolvePublic(uri.host);
    _active(epoch);
    final client = _client(uri, address);
    _httpRequests.add(client);
    try {
      final outbound = await client.openUrl(method, uri)
          .timeout(const Duration(seconds: 6));
      _active(epoch);
      outbound.followRedirects = false;
      outbound.persistentConnection = false;
      outbound.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain');
      outbound.headers.removeAll(HttpHeaders.acceptEncodingHeader);
      if (method == 'POST') {
        outbound.headers.contentType = ContentType.json;
        outbound.add(utf8.encode(body));
      }
      final response = await outbound.close()
          .timeout(const Duration(seconds: 10));
      _active(epoch);
      if (response.isRedirect) {
        throw StateError('Redirect rejected: approve the exact server');
      }
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 8))) {
        _active(epoch);
        if (bytes.length + part.length > GameNetworkPolicy.maxResponseBytes) {
          throw StateError('Server response exceeds 64KiB');
        }
        bytes.addAll(part);
      }
      _active(epoch);
      return {
        'status': response.statusCode,
        'text': utf8.decode(bytes, allowMalformed: false),
      };
    } finally {
      _httpRequests.remove(client);
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> connect(Uri uri) async {
    if (_connecting || _socket != null) {
      throw StateError('Only one active WebSocket per mini-app');
    }
    final epoch = _epoch;
    _active(epoch);
    _connecting = true;
    HttpClient? client;
    try {
      final address = await GameNetworkPolicy.resolvePublic(uri.host);
      _active(epoch);
      client = _client(uri, address);
      final socket = await WebSocket.connect(uri.toString(),
        customClient: client,
        compression: CompressionOptions.compressionOff,
        maxPayloadLength: GameNetworkPolicy.maxMessageBytes,
      ).timeout(const Duration(seconds: 8));
      if (!_foreground || epoch != _epoch) {
        await socket.close(WebSocketStatus.normalClosure);
        throw StateError('WebSocket connection cancelled when backgrounded');
      }
      _queue.clear();
      _dropped = 0;
      _socket = socket;
      _webSocketClient = client;
      socket.pingInterval = const Duration(seconds: 25);
      _listener = socket.listen((dynamic payload) {
        if (!_foreground || epoch != _epoch) return;
        if (payload is! String ||
            utf8.encode(payload).length > GameNetworkPolicy.maxMessageBytes) {
          unawaited(socket.close(WebSocketStatus.messageTooBig));
          return;
        }
        if (_queue.length >= GameNetworkPolicy.maxQueuedMessages) {
          _queue.removeFirst();
          _dropped++;
        }
        _queue.addLast(payload);
      }, onError: (Object _) => close(), onDone: close, cancelOnError: true);
      return {'connected': true, 'origin': GameNetworkPolicy.origin(uri)};
    } catch (_) {
      client?.close(force: true);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  bool send(String text) {
    if (!connected) return false;
    if (utf8.encode(text).length > GameNetworkPolicy.maxMessageBytes) {
      throw const FormatException('Game message exceeds 8KiB');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSendMs < 50) {
      throw StateError('Messages are limited to 20 per second');
    }
    _lastSendMs = now;
    _socket!.add(text);
    return true;
  }

  Map<String, dynamic> poll() {
    final out = <String>[];
    while (out.length < 16 && _queue.isNotEmpty) {
      out.add(_queue.removeFirst());
    }
    return {'connected': connected, 'messages': out, 'dropped': _dropped};
  }

  void close() {
    final socket = _socket;
    _socket = null;
    final listener = _listener;
    _listener = null;
    if (listener != null) unawaited(listener.cancel());
    if (socket != null) {
      unawaited(socket.close(WebSocketStatus.normalClosure));
    }
    _webSocketClient?.close(force: true);
    _webSocketClient = null;
    _queue.clear();
    _dropped = 0;
  }
}
