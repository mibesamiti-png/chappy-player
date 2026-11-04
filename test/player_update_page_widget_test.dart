import 'dart:io';

import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/screens/player_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('private repository without public feed shows safe disabled state',
      (tester) async {
    if (!Platform.isAndroid) {
      await tester.pumpWidget(MaterialApp(
        home: PlayerUpdatePage(logs: LogStore()),
      ));
      expect(find.text('プレイヤー本体の更新'), findsOneWidget);
      expect(find.text('最新版を確認'), findsOneWidget);
      expect(find.textContaining('更新配信先はまだ未設定'), findsOneWidget);
      final check = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '最新版を確認'),
      );
      expect(check.onPressed, isNull);
    }
  });
}
