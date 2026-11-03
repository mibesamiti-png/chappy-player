import 'dart:io';

import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/screens/logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture starts, records, stops, and remains exportable',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('chappy_widget_logs_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final logs = LogStore();
    await logs.init(baseDirectory: temp);

    await tester.pumpWidget(MaterialApp(
      home: LogsPage(logs: logs, appId: 'local.chappy.memo'),
    ));
    expect(find.text('記録開始'), findsOneWidget);
    await tester.tap(find.text('記録開始'));
    await tester.pumpAndSettle();

    expect(logs.diagnosticSession!.isRecording, isTrue);
    await logs.add('local.chappy.memo', 'error', 'test', 'simulated failure');
    await tester.tap(find.byTooltip('表示ログを更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1件'), findsOneWidget);

    await tester.tap(find.text('記録終了'));
    await tester.pumpAndSettle();
    expect(logs.diagnosticSession!.isRecording, isFalse);
    expect(logs.diagnosticSessionReport(), contains('simulated failure'));
    expect(find.text('記録開始'), findsOneWidget);
  });
}
