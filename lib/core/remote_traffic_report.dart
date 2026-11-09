import 'dart:convert';
import 'dart:typed_data';

/// Host-only, owner-supplied local JSON. Never packet capture or JS bridge.
class RemoteTrafficSample {
  final int rxBytes;
  final int txBytes;
  const RemoteTrafficSample(this.rxBytes, this.txBytes);
}

class RemoteTrafficReport {
  static const format = 'chappy.remote-traffic.v1';
  static const maxFileBytes = 16 * 1024;
  static const maxCounter = (1 << 52) - 1;
  final List<RemoteTrafficSample> samples;
  final int totalRxBytes;
  final int totalTxBytes;

  const RemoteTrafficReport._(this.samples, this.totalRxBytes, this.totalTxBytes);
  int get seconds => samples.length;
  double get avgRxBytesPerSecond => totalRxBytes / seconds;
  double get avgTxBytesPerSecond => totalTxBytes / seconds;
  int get peakRxBytesPerSecond =>
      samples.fold<int>(0, (n, s) => s.rxBytes > n ? s.rxBytes : n);
  int get peakTxBytesPerSecond =>
      samples.fold<int>(0, (n, s) => s.txBytes > n ? s.txBytes : n);

  static int _counter(Object? value) {
    if (value is! int || value < 0 || value > maxCounter) {
      throw const FormatException('通信量の値が不正です');
    }
    return value;
  }

  static bool _keys(Map<dynamic, dynamic> data, Set<String> keys) {
    if (data.keys.any((key) => key is! String)) return false;
    final actual = data.keys.cast<String>().toSet();
    return actual.length == keys.length && actual.containsAll(keys);
  }

  static RemoteTrafficReport parseBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('通信レポートは16KiB以下のJSONのみ対応します');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw const FormatException('JSONを読み取れません');
    }
    if (decoded is! Map ||
        !_keys(decoded, {'format', 'source', 'coverage', 'interval_ms',
                         'samples', 'totals'}) ||
        decoded['format'] != format ||
        decoded['source'] != 'windows_pc' ||
        decoded['coverage'] != 'all_interfaces' ||
        decoded['interval_ms'] != 1000) {
      throw const FormatException('未対応の通信レポート形式です');
    }
    final rawSamples = decoded['samples'];
    if (rawSamples is! List || rawSamples.length < 5 ||
        rawSamples.length > 30) {
      throw const FormatException('計測件数は5～30件に限ります');
    }
    var rx = 0;
    var tx = 0;
    final points = <RemoteTrafficSample>[];
    for (final raw in rawSamples) {
      if (raw is! Map || !_keys(raw, {'rx_bytes', 'tx_bytes'})) {
        throw const FormatException('未知のレポート項目があります');
      }
      final a = _counter(raw['rx_bytes']);
      final b = _counter(raw['tx_bytes']);
      rx += a;
      tx += b;
      if (rx > maxCounter || tx > maxCounter) {
        throw const FormatException('通信量の合計が大きすぎます');
      }
      points.add(RemoteTrafficSample(a, b));
    }
    final totals = decoded['totals'];
    if (totals is! Map ||
        !_keys(totals, {'rx_bytes', 'tx_bytes'}) ||
        _counter(totals['rx_bytes']) != rx ||
        _counter(totals['tx_bytes']) != tx) {
      throw const FormatException('通信量の合計が一致しません');
    }
    return RemoteTrafficReport._(List.unmodifiable(points), rx, tx);
  }
}
