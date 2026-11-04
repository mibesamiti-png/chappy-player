import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/screens/self_check_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('on-device self-check screen explains scope and has run button',
      (tester) async {
    // No I/O in FakeAsync widget tests. Service I/O is covered by its own tests.
    await tester.pumpWidget(MaterialApp(
      home: SelfCheckPage(
        repository: PackageRepository(),
        logs: LogStore(),
      ),
    ));
    expect(find.text('端末セルフチェック'), findsOneWidget);
    expect(find.text('セルフチェックを実行'), findsOneWidget);
    expect(find.byTooltip('結果をコピー'), findsOneWidget);
    expect(find.textContaining('WebView実描画'), findsOneWidget);
  });
}
