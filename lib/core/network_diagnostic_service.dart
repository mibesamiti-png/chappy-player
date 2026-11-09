import 'dart:async';
import 'dart:io';

/// No polling, subnet scans, raw packets, IP addresses or persisted logs.
/// All external probes go ONLY to the clearly disclosed example.com host.
class NetworkDiagnosticSnapshot {
  final int interfaceCount;
  final bool dnsResolved;
  final int? httpsStatus;
  final String? stoppedAt;

  const NetworkDiagnosticSnapshot({
    required this.interfaceCount,
    required this.dnsResolved,
    required this.httpsStatus,
    required this.stoppedAt,
  });

  bool get httpsResponded => httpsStatus != null;
}

/// Each instance performs at most one explicit user-initiated run.
/// Tests inject probe functions and never contact external hosts.
class NetworkDiagnosticService {
  final Future<int> Function()? interfaceProbe;
  final Future<bool> Function()? dnsProbe;
  final Future<int?> Function()? httpsProbe;
  HttpClient? _client;
  bool _cancelled = false;
  bool _ran = false;

  NetworkDiagnosticService({
    this.interfaceProbe,
    this.dnsProbe,
    this.httpsProbe,
  });

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _client = null;
  }

  Future<NetworkDiagnosticSnapshot> run() async {
    if (_ran || _cancelled) throw StateError('One diagnostic per session');
    _ran = true;
    var count = 0;
    var dns = false;
    int? code;
    String? stopped;
    try {
      count = await (interfaceProbe ?? _interfaces)()
          .timeout(const Duration(seconds: 5));
      if (_cancelled) return _result(count, dns, code, 'cancelled');
      if (count <= 0) return _result(0, false, null, 'no_interface');
    } catch (_) {
      return _result(count, dns, code, 'interface');
    }
    try {
      dns = await (dnsProbe ?? _dns)()
          .timeout(const Duration(seconds: 5));
      if (_cancelled) return _result(count, dns, code, 'cancelled');
      if (!dns) return _result(count, false, null, 'dns');
    } catch (_) {
      return _result(count, false, null, 'dns');
    }
    try {
      code = await (httpsProbe ?? _https)()
          .timeout(const Duration(seconds: 8));
      if (_cancelled) return _result(count, dns, null, 'cancelled');
      if (code == null) stopped = 'https';
    } catch (_) {
      stopped = 'https';
    } finally {
      _client?.close(force: true);
      _client = null;
    }
    return _result(count, dns, code, stopped);
  }

  static NetworkDiagnosticSnapshot _result(
      int count, bool dns, int? code, String? stopped) =>
      NetworkDiagnosticSnapshot(
        interfaceCount: count < 0 ? 0 : count,
        dnsResolved: dns,
        httpsStatus: code,
        stoppedAt: stopped,
      );

  static Future<int> _interfaces() async {
    final all = await NetworkInterface.list(
      type: InternetAddressType.any,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    // Intentionally discard all interface names, MACs and IP addresses.
    return all.length;
  }

  static Future<bool> _dns() async =>
      (await InternetAddress.lookup('example.com')).isNotEmpty;

  Future<int?> _https() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..userAgent = null;
    _client = client;
    try {
      if (_cancelled) return null;
      final request = await client.headUrl(
        Uri.parse('https://example.com/'),
      ).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.persistentConnection = false;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      return response.statusCode; // No body, cookie store or location logged.
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}
