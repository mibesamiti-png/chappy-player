import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/screens/logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('diagnostic screen renders empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LogsPage(logs: LogStore())));
    expect(find.text('診断ログ'), findsOneWidget);
    expect(find.text('該当するログはありません'), findsOneWidget);
  });
}
