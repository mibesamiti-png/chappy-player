import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/remote_traffic_report.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> exampleReport() => <String, dynamic>{
  'format': 'chappy.remote-traffic.v1',
  'source': 'windows_pc',
  'coverage': 'all_interfaces',
  'interval_ms': 1000,
  'samples': List.generate(5,
      (i) => <String, int>{'rx_bytes': 100 + i, 'tx_bytes': 20 + i}),
  'totals': <String, int>{'rx_bytes': 510, 'tx_bytes': 110},
};

Uint8List encode(Map<String, dynamic> obj) =>
    Uint8List.fromList(utf8.encode(jsonEncode(obj)));

void main() {
  test('valid format and totals, average and peak', () {
    final r = RemoteTrafficReport.parseBytes(encode(exampleReport()));
    expect(r.seconds, 5);
    expect(r.totalRxBytes, 510);
    expect(r.totalTxBytes, 110);
    expect(r.peakRxBytesPerSecond, 104);
    expect(r.peakTxBytesPerSecond, 24);
    expect(r.avgRxBytesPerSecond, 102);
  });

  test('unknown identifiers, forged totals and invalid fields fail closed', () {
    final malformed = <Map<String, dynamic>>[
      {...exampleReport(), 'hostname': 'private'},
      {...exampleReport(), 'source': 'unknown'},
      {...exampleReport(), 'coverage': 'wifi_only'},
      {...exampleReport(), 'interval_ms': 500},
      {...exampleReport(), 'totals': {'rx_bytes': 509, 'tx_bytes': 110}},
      {...exampleReport(), 'samples': []},
      {...exampleReport(), 'samples': List.generate(31,
          (i) => <String, int>{'rx_bytes': 0, 'tx_bytes': 0})},
      {...exampleReport(), 'samples': [
        {'rx_bytes': 100, 'tx_bytes': 20, 'ip': '10.0.0.8'},
        ...List.generate(4, (i) => {'rx_bytes': 100, 'tx_bytes': 20}),
      ]},
      {...exampleReport(), 'samples': [
        {'rx_bytes': -1, 'tx_bytes': 20},
        ...List.generate(4, (i) => {'rx_bytes': 100, 'tx_bytes': 20}),
      ]},
    ];
    for (final obj in malformed) {
      expect(() => RemoteTrafficReport.parseBytes(encode(obj)),
          throwsFormatException, reason: jsonEncode(obj));
    }
  });

  test('oversized and non-UTF8 data rejected', () {
    expect(() => RemoteTrafficReport.parseBytes(Uint8List(0)),
        throwsFormatException);
    expect(() => RemoteTrafficReport.parseBytes(Uint8List(16385)),
        throwsFormatException);
    expect(() => RemoteTrafficReport.parseBytes(Uint8List.fromList([255])),
        throwsFormatException);
    expect(() => RemoteTrafficReport.parseBytes(
        Uint8List.fromList(utf8.encode('null'))), throwsFormatException);
  });
}
