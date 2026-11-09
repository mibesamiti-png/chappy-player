import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/screens/remote_traffic_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List reportBytes() => Uint8List.fromList(utf8.encode(jsonEncode({
  'format': 'chappy.remote-traffic.v1', 'source': 'windows_pc',
  'coverage': 'all_interfaces', 'interval_ms': 1000,
  'samples': List.generate(5, (_) => {'rx_bytes': 100, 'tx_bytes': 10}),
  'totals': {'rx_bytes': 500, 'tx_bytes': 50},
})));

void main() {
  testWidgets('no file read until distinct owner consent, clear on demand',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: RemoteTrafficImportPage(
      pickReport: () async { calls++; return reportBytes(); },
    )));
    expect(calls, 0);
    expect(find.byKey(const Key('remote_traffic_summary')), findsNothing);
    await tester.tap(find.byKey(const Key('remote_traffic_import')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byKey(const Key('remote_traffic_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote_traffic_approve')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('計測時間: 5秒'), findsOneWidget);
    expect(find.byKey(const Key('remote_traffic_rx')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('remote_traffic_clear')), 200);
    await tester.tap(find.byKey(const Key('remote_traffic_clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_traffic_summary')), findsNothing);
  });

  testWidgets('unknown JSON is rejected, no report shown', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RemoteTrafficImportPage(
      pickReport: () async => Uint8List.fromList([123, 125]),
    )));
    await tester.tap(find.byKey(const Key('remote_traffic_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote_traffic_approve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_traffic_summary')), findsNothing);
    expect(find.byKey(const Key('remote_traffic_notice')), findsOneWidget);
  });

  testWidgets('background discards pending file and prevents late display',
      (tester) async {
    final pending = Completer<Uint8List?>();
    await tester.pumpWidget(MaterialApp(home: RemoteTrafficImportPage(
      pickReport: () => pending.future,
    )));
    await tester.tap(find.byKey(const Key('remote_traffic_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote_traffic_approve')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(reportBytes());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remote_traffic_summary')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
