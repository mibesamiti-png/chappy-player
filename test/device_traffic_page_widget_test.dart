import 'package:chappy_player/core/device_traffic_client.dart';
import 'package:chappy_player/screens/device_traffic_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  var reads = 0;

  setUp(() {
    reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'trafficSnapshot') {
        throw PlatformException(code: 'UNEXPECTED');
      }
      reads++;
      return <String, dynamic>{
        'source': DeviceTrafficSnapshot.source,
        'elapsedMs': reads * 1000,
        'supported': true,
        'rxBytes': 1000 + reads * 800,
        'txBytes': 2000 + reads * 400,
        'appSupported': true,
        'appRxBytes': 100 + reads * 100,
        'appTxBytes': 50 + reads * 80,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('no traffic read until explicit user confirmation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DeviceTrafficPage(client: DeviceTrafficClient(channel: channel)),
    ));
    expect(reads, 0);
    expect(find.text('計測停止中'), findsOneWidget);
    await tester.tap(find.byKey(const Key('traffic_start')));
    await tester.pumpAndSettle();
    expect(find.text('60秒間計測する'), findsOneWidget);
    expect(reads, 0);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(reads, 0);
  });

  testWidgets('samples only during the session and stops manually',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DeviceTrafficPage(client: DeviceTrafficClient(channel: channel)),
    ));
    await tester.tap(find.byKey(const Key('traffic_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60秒間計測する'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(reads, greaterThanOrEqualTo(1));
    expect(find.textContaining('計測中'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(reads, greaterThanOrEqualTo(2));
    expect(find.textContaining('800 B/秒'), findsOneWidget);
    expect(find.textContaining('400 B/秒'), findsOneWidget);

    await tester.tap(find.byKey(const Key('traffic_stop')));
    await tester.pump();
    expect(find.text('計測停止中'), findsOneWidget);
    final stoppedAt = reads;
    await tester.pump(const Duration(seconds: 4));
    expect(reads, stoppedAt);
  });

  testWidgets('background transition stops collection and does not restart',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DeviceTrafficPage(client: DeviceTrafficClient(channel: channel)),
    ));
    await tester.tap(find.byKey(const Key('traffic_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60秒間計測する'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('計測停止中'), findsOneWidget);
    final stoppedAt = reads;
    await tester.pump(const Duration(seconds: 4));
    expect(reads, stoppedAt);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('計測停止中'), findsOneWidget);
  });

  testWidgets('auto stops after the 60 second time limit', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DeviceTrafficPage(client: DeviceTrafficClient(channel: channel)),
    ));
    await tester.tap(find.byKey(const Key('traffic_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60秒間計測する'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.text('計測停止中'), findsOneWidget);
    expect(find.textContaining('60秒経過'), findsOneWidget);
  });
}
