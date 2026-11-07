import 'package:chappy_player/core/device_traffic_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.chappy.player/network_lab');

  test('parses supported Android device and own app counters', () {
    final snapshot = DeviceTrafficSnapshot.fromWire(<String, dynamic>{
      'source': DeviceTrafficSnapshot.source,
      'elapsedMs': 1400,
      'supported': true,
      'rxBytes': 12288,
      'txBytes': 4096,
      'appSupported': true,
      'appRxBytes': 100,
      'appTxBytes': 90,
    });
    expect(snapshot.supported, isTrue);
    expect(snapshot.rxBytes, 12288);
    expect(snapshot.txBytes, 4096);
    expect(snapshot.appRxBytes, 100);
  });

  test('unsupported metrics stay missing, never masquerade as zero', () {
    final snapshot = DeviceTrafficSnapshot.fromWire(<String, dynamic>{
      'source': DeviceTrafficSnapshot.source,
      'elapsedMs': 10,
      'supported': false,
      'rxBytes': null,
      'txBytes': null,
      'appSupported': false,
      'appRxBytes': null,
      'appTxBytes': null,
    });
    expect(snapshot.supported, isFalse);
    expect(snapshot.rxBytes, isNull);
    expect(snapshot.since(snapshot), isNull);
  });

  test('calculates per-second rates using monotonic sample time', () {
    const previous = DeviceTrafficSnapshot(
      elapsedMs: 10000,
      rxBytes: 1000,
      txBytes: 2000,
      appRxBytes: 400,
      appTxBytes: 800,
    );
    const latest = DeviceTrafficSnapshot(
      elapsedMs: 12000,
      rxBytes: 5000,
      txBytes: 3000,
      appRxBytes: 1400,
      appTxBytes: 1000,
    );
    final rate = latest.since(previous)!;
    expect(rate.receivedPerSecond, 2000);
    expect(rate.sentPerSecond, 500);
    expect(rate.appReceivedPerSecond, 500);
    expect(rate.appSentPerSecond, 100);
  });

  test('boot reset, zero time and decreasing counters never synthesize rate', () {
    const original = DeviceTrafficSnapshot(
      elapsedMs: 2000,
      rxBytes: 5000,
      txBytes: 3000,
      appRxBytes: 500,
      appTxBytes: 300,
    );
    expect(const DeviceTrafficSnapshot(
      elapsedMs: 100,
      rxBytes: 5,
      txBytes: 3,
      appRxBytes: 1,
      appTxBytes: 1,
    ).since(original), isNull);
    expect(const DeviceTrafficSnapshot(
      elapsedMs: 2000,
      rxBytes: 6000,
      txBytes: 4000,
      appRxBytes: 600,
      appTxBytes: 400,
    ).since(original), isNull);
    expect(const DeviceTrafficSnapshot(
      elapsedMs: 2400,
      rxBytes: 4900,
      txBytes: 4000,
      appRxBytes: 500,
      appTxBytes: 400,
    ).since(original), isNull);
  });

  test('app-only reset never mislabels whole-device speed', () {
    const original = DeviceTrafficSnapshot(
      elapsedMs: 1000,
      rxBytes: 1000,
      txBytes: 1000,
      appRxBytes: 800,
      appTxBytes: 700,
    );
    const latest = DeviceTrafficSnapshot(
      elapsedMs: 2000,
      rxBytes: 1100,
      txBytes: 1150,
      appRxBytes: 200,
      appTxBytes: 500,
    );
    final rate = latest.since(original)!;
    expect(rate.receivedPerSecond, 100);
    expect(rate.sentPerSecond, 150);
    expect(rate.appReceivedPerSecond, isNull);
    expect(rate.appSentPerSecond, isNull);
  });

  test('malformed untrusted MethodChannel results fail closed', () {
    final invalid = <Map<String, dynamic>>[
      <String, dynamic>{'source': 'other', 'elapsedMs': 1000},
      <String, dynamic>{'source': DeviceTrafficSnapshot.source,
          'elapsedMs': -1},
      <String, dynamic>{'source': DeviceTrafficSnapshot.source,
          'elapsedMs': 200, 'supported': true, 'rxBytes': -1,
          'txBytes': 100},
      <String, dynamic>{'source': DeviceTrafficSnapshot.source,
          'elapsedMs': 200, 'appSupported': true, 'appRxBytes': null,
          'appTxBytes': null},
    ];
    for (final map in invalid) {
      expect(() => DeviceTrafficSnapshot.fromWire(map),
          throwsFormatException);
    }
  });

  test('typed client reads traffic only when explicitly invoked', () async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'trafficSnapshot');
      reads++;
      return <String, dynamic>{
        'source': DeviceTrafficSnapshot.source,
        'elapsedMs': 1000,
        'supported': true,
        'rxBytes': 100,
        'txBytes': 50,
        'appSupported': false,
      };
    });
    try {
      const client = DeviceTrafficClient(channel: channel);
      expect(reads, 0);
      final data = await client.snapshot();
      expect(reads, 1);
      expect(data.rxBytes, 100);
      expect(data.appRxBytes, isNull);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
