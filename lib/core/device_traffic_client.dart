import 'package:flutter/services.dart';

/// Trusted-host-only read of Android TrafficStats counters.
/// No .chappy JavaScript bridge, network calls, Android usage access, or VPN.
class DeviceTrafficClient {
  final MethodChannel _channel;
  const DeviceTrafficClient({
    MethodChannel channel =
        const MethodChannel('dev.chappy.player/network_lab'),
  }) : _channel = channel;

  Future<DeviceTrafficSnapshot> snapshot() async {
    final reply =
        await _channel.invokeMapMethod<String, dynamic>('trafficSnapshot');
    return DeviceTrafficSnapshot.fromWire(reply);
  }
}

class DeviceTrafficSnapshot {
  static const source = 'android.trafficstats.since_boot';

  final int elapsedMs;
  final int? rxBytes;
  final int? txBytes;
  final int? appRxBytes;
  final int? appTxBytes;

  const DeviceTrafficSnapshot({
    required this.elapsedMs,
    required this.rxBytes,
    required this.txBytes,
    required this.appRxBytes,
    required this.appTxBytes,
  });

  static int? _nonnegative(dynamic value) =>
      value is int && value >= 0 ? value : null;

  factory DeviceTrafficSnapshot.fromWire(Map<String, dynamic>? raw) {
    if (raw == null || raw['source'] != source) {
      throw const FormatException('Invalid Android traffic statistics source');
    }
    final uptime = _nonnegative(raw['elapsedMs']);
    if (uptime == null) {
      throw const FormatException('Invalid traffic sample timestamp');
    }
    final supported = raw['supported'] == true;
    final appSupported = raw['appSupported'] == true;
    final rx = _nonnegative(raw['rxBytes']);
    final tx = _nonnegative(raw['txBytes']);
    final appRx = _nonnegative(raw['appRxBytes']);
    final appTx = _nonnegative(raw['appTxBytes']);
    if (supported && (rx == null || tx == null)) {
      throw const FormatException('Missing device traffic counters');
    }
    if (appSupported && (appRx == null || appTx == null)) {
      throw const FormatException('Missing app traffic counters');
    }
    return DeviceTrafficSnapshot(
      elapsedMs: uptime,
      rxBytes: supported ? rx : null,
      txBytes: supported ? tx : null,
      appRxBytes: appSupported ? appRx : null,
      appTxBytes: appSupported ? appTx : null,
    );
  }

  bool get supported => rxBytes != null && txBytes != null;

  /// Rate cannot be inferred from a single snapshot, counter reset, or
  /// unknown/unsupported platform reading. Missing samples are not zero.
  DeviceTrafficRate? since(DeviceTrafficSnapshot older) {
    if (!supported || !older.supported || elapsedMs <= older.elapsedMs) {
      return null;
    }
    final deltaRx = rxBytes! - older.rxBytes!;
    final deltaTx = txBytes! - older.txBytes!;
    if (deltaRx < 0 || deltaTx < 0) return null;
    final elapsed = elapsedMs - older.elapsedMs;
    double? appRxRate;
    double? appTxRate;
    if (appRxBytes != null &&
        appTxBytes != null &&
        older.appRxBytes != null &&
        older.appTxBytes != null &&
        appRxBytes! >= older.appRxBytes! &&
        appTxBytes! >= older.appTxBytes!) {
      appRxRate = (appRxBytes! - older.appRxBytes!) * 1000 / elapsed;
      appTxRate = (appTxBytes! - older.appTxBytes!) * 1000 / elapsed;
    }
    return DeviceTrafficRate(
      receivedPerSecond: deltaRx * 1000 / elapsed,
      sentPerSecond: deltaTx * 1000 / elapsed,
      appReceivedPerSecond: appRxRate,
      appSentPerSecond: appTxRate,
    );
  }
}

class DeviceTrafficRate {
  final double receivedPerSecond;
  final double sentPerSecond;
  final double? appReceivedPerSecond;
  final double? appSentPerSecond;

  const DeviceTrafficRate({
    required this.receivedPerSecond,
    required this.sentPerSecond,
    required this.appReceivedPerSecond,
    required this.appSentPerSecond,
  });
}
