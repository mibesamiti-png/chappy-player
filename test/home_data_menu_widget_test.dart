import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home data management menu and file import', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(repository: PackageRepository(), logs: LogStore()),
    ));
    expect(find.text('サンプルメモ帳を追加してテスト'), findsNothing);
    expect(find.text('Chappy Apps 公開ライブラリ'), findsOneWidget);
    expect(find.text('保存データをバックアップ'), findsNothing);
    await tester.tap(find.byKey(const Key('home_data_menu')));
    await tester.pumpAndSettle();
    expect(find.text('保存データをバックアップ'), findsOneWidget);
    expect(find.text('保存データを復元'), findsOneWidget);
  });
}
