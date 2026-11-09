import 'dart:convert';

import 'package:crypto/crypto.dart';

/// QR-v3-only, separately consented one-time PC status read (never control).
/// No secrets, arbitrary files, app names or network metadata are represented.
class PcStatusOnceMetrics {
  final bool available;
  final int? logicalCpus;
  final int? memoryTotalBytes;
  final int? memoryAvailableBytes;
  final int? uptimeSeconds;

  const PcStatusOnceMetrics({
    required this.available,
    this.logicalCpus,
    this.memoryTotalBytes,
    this.memoryAvailableBytes,
    this.uptimeSeconds,
  });

  static PcStatusOnceMetrics parse(Map<dynamic, dynamic> raw) {
    const keys = <String>{
      'available', 'logical_cpus', 'memory_total_bytes',
      'memory_available_bytes', 'uptime_seconds',
    };
    if (raw.length != keys.length ||
        raw.keys.toSet().difference(keys).isNotEmpty ||
        raw['available'] is! bool) {
      throw const FormatException('PC状態の項目が不正です');
    }
    final values = <String, int?>{};
    for (final key in keys.where((item) => item != 'available')) {
      final value = raw[key];
      if (value != null && (value is! int || value < 0)) {
        throw const FormatException('PC状態の数値が不正です');
      }
      values[key] = value as int?;
    }
    final total = values['memory_total_bytes'];
    final free = values['memory_available_bytes'];
    if ((total != null && free != null && free > total) ||
        (raw['available'] == false && values.values.any((v) => v != null))) {
      throw const FormatException('PC状態が矛盾しています');
    }
    return PcStatusOnceMetrics(
      available: raw['available'] as bool,
      logicalCpus: values['logical_cpus'],
      memoryTotalBytes: total,
      memoryAvailableBytes: free,
      uptimeSeconds: values['uptime_seconds'],
    );
  }
}

/// A domain-separated nonce preserves existing native P-256/KeyStore signing
/// while cryptographically binding status usage to pc.status.read.
String pcStatusScopedNonce(String rawHex) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHex)) {
    throw const FormatException('状態取得の認証用乱数が不正です');
  }
  final bytes = <int>[
    ...utf8.encode('CHAPPY-PC-STATUS-READ-V1'),
    0,
    for (var i = 0; i < rawHex.length; i += 2)
      int.parse(rawHex.substring(i, i + 2), radix: 16),
  ];
  return sha256.convert(bytes).toString();
}
