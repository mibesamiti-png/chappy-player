import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first-run home exposes bundled memo install without a picker',
      (tester) async {
    // Disk behavior is tested by package_repository_recovery_test.dart.
    // FakeAsync widget tests must not perform real file operations.
    final repo = PackageRepository();
    final logs = LogStore();
    await tester.pumpWidget(MaterialApp(
      home: HomePage(repository: repo, logs: logs),
    ));
    final button = find.text('サンプルメモ帳を追加してテスト');
    await tester.ensureVisible(button);
    expect(button, findsOneWidget);
    final action = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(action.onPressed, isNotNull);
  });
}
