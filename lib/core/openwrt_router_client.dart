import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/router_connection_snapshot.dart';
import 'package:crypto/crypto.dart';

/// OpenWrt LuCI read-only ubus access. HTTPS certificate SHA-256 pin REQUIRED.
/// No HTTP fallback, router discovery, shell/RPC execution, credential cache,
/// mini-app JS bridge, or recurring/background polling.
class OpenWrtRouterClient {
  HttpClient? _active;
  bool _cancelled = false;
  bool _used = false;
  int _nextId = 1;

  void cancel() {
    _cancelled = true;
    _active?.close(force: true);
    _active = null;
  }

  void _activeOrThrow() {
    if (_cancelled) throw StateError('取得は中止されました');
  }

  static void validateRouter({
    required String ip,
    required int port,
    required String tlsFingerprint,
    required String deviceIp,
    required String username,
    required String password,
  }) {
    if (!RouterConntrackContract.isPrivateIpv4(ip) ||
        !RouterConntrackContract.isPrivateIpv4(deviceIp) ||
        ip == deviceIp || port < 1 || port > 65535) {
      throw const FormatException('ルーターと対象端末のIPv4/ポートを確認してください');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(tlsFingerprint)) {
      throw const FormatException('ルーター証明書のSHA-256指紋64桁が必要です');
    }
    if (username.isEmpty || username.length > 64 ||
        username.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        password.isEmpty || password.length > 256) {
      throw const FormatException('ルーターのユーザー名とパスワードが不正です');
    }
  }

  /// One explicit owner request: session.login -> DHCP hints -> conntrack.
  /// The caller validates foreground Wi-Fi before and after each operation.
  /// A short-lived session ID and router credentials never leave this method.
  Future<RouterConnectionSnapshot> readOnce({
    required String routerIp,
    required int port,
    required String tlsFingerprint,
    required String deviceIp,
    required String username,
    required String password,
    required Future<bool> Function() approvedWifi,
  }) async {
    if (_used || _cancelled) {
      throw StateError('ルーター情報の再取得には画面を開き直してください');
    }
    _used = true;
    validateRouter(ip: routerIp, port: port,
        tlsFingerprint: tlsFingerprint, deviceIp: deviceIp,
        username: username, password: password);
    if (!await approvedWifi()) {
      throw StateError('前面表示中のWi-Fi接続だけに対応しています');
    }
    _activeOrThrow();

    // Empty trust store forces explicit SHA-256 validation even for public CA
    // certs. The response cert is ALSO verified, never just trust callback.
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    client.connectionTimeout = const Duration(seconds: 6);
    client.idleTimeout = const Duration(seconds: 1);
    client.autoUncompress = false;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = (certificate, host, certificatePort) {
      return host == routerIp && certificatePort == port &&
          sha256.convert(certificate.der).toString() == tlsFingerprint;
    };
    _active = client;
    try {
      final login = await _call(
        client: client, routerIp: routerIp, port: port,
        tlsPin: tlsFingerprint,
        token: '00000000000000000000000000000000',
        object: 'session', method: 'login',
        args: {'username': username, 'password': password, 'timeout': 60},
      );
      _activeOrThrow();
      final token = login['ubus_rpc_session'];
      if (token is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
        throw const FormatException('OpenWrtから安全な認証セッションを取得できません');
      }
      if (!await approvedWifi()) {
        throw StateError('Wi-Fi接続状態が変わりました');
      }
      _activeOrThrow();
      final leases = await _call(
        client: client, routerIp: routerIp, port: port,
        tlsPin: tlsFingerprint, token: token,
        object: 'luci-rpc', method: 'getDHCPLeases', args: const {},
      );
      if (!await approvedWifi()) {
        throw StateError('Wi-Fi接続状態が変わりました');
      }
      _activeOrThrow();
      final flows = await _call(
        client: client, routerIp: routerIp, port: port,
        tlsPin: tlsFingerprint, token: token,
        object: 'luci', method: 'getConntrackList', args: const {},
      );
      _activeOrThrow();
      if (!await approvedWifi()) {
        throw StateError('Wi-Fi接続状態が変わりました');
      }
      final snapshot = RouterConntrackContract.parse(
        deviceIp: deviceIp,
        rawList: flows['result'],
        rawLeases: leases,
      );
      _activeOrThrow();
      return snapshot;
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
      _cancelled = true; // The whole session is one-shot, including failures.
    }
  }

  Future<Map<String, dynamic>> _call({
    required HttpClient client,
    required String routerIp,
    required int port,
    required String tlsPin,
    required String token,
    required String object,
    required String method,
    required Map<String, Object> args,
  }) async {
    _activeOrThrow();
    // No arbitrary ubus object or command may reach the router.
    if (!((object == 'session' && method == 'login') ||
        (object == 'luci-rpc' && method == 'getDHCPLeases') ||
        (object == 'luci' && method == 'getConntrackList'))) {
      throw StateError('許可されていないルーター操作です');
    }
    final requestId = _nextId++;
    final payload = utf8.encode(jsonEncode({
      'jsonrpc': '2.0', 'id': requestId, 'method': 'call',
      'params': [token, object, method, args],
    }));
    if (payload.length > 2048) {
      throw const FormatException('ルーターへの要求が大きすぎます');
    }
    try {
      final req = await client.postUrl(Uri(
        scheme: 'https', host: routerIp, port: port, path: '/ubus',
      )).timeout(const Duration(seconds: 7));
      _activeOrThrow();
      req
        ..followRedirects = false
        ..persistentConnection = false
        ..headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      req.add(payload);
      final response = await req.close().timeout(const Duration(seconds: 8));
      _activeOrThrow();
      if (response.statusCode != HttpStatus.ok ||
          response.isRedirect ||
          response.certificate == null ||
          sha256.convert(response.certificate!.der).toString() != tlsPin) {
        throw StateError('HTTPS証明書が一致しないか、OpenWrtが応答していません');
      }
      if (response.contentLength >
          RouterConntrackContract.maxReplyBytes) {
        throw const FormatException('ルーターの応答サイズが上限を超えています');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(
          const Duration(seconds: 9))) {
        _activeOrThrow();
        if (bytes.length + chunk.length >
            RouterConntrackContract.maxReplyBytes) {
          throw const FormatException('ルーターの応答が大きすぎます');
        }
        bytes.add(chunk);
      }
      final data = jsonDecode(utf8.decode(
          bytes.takeBytes(), allowMalformed: false));
      if (data is! Map<String, dynamic> ||
          data['jsonrpc'] != '2.0' || data['id'] != requestId ||
          data['error'] != null) {
        throw const FormatException('OpenWrt JSON-RPC応答が不正です');
      }
      final result = data['result'];
      if (result is! List || result.length != 2 ||
          result[0] != 0 || result[1] is! Map<String, dynamic>) {
        throw StateError('ルーター側が権限を拒否したかAPIに対応していません');
      }
      return result[1] as Map<String, dynamic>;
    } on TimeoutException {
      throw StateError('ルーターのHTTPS応答がタイムアウトしました');
    }
  }
}
