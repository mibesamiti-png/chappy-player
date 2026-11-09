import 'package:chappy_player/screens/buffalo_inventory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BUFFALO inventory is offline and needs router-owner consent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BuffaloInventoryPage()));
    expect(find.text('BUFFALO 端末一覧'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_inventory_import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final action = tester.widget<FilledButton>(
      find.byKey(const Key('buffalo_inventory_import')),
    );
    expect(action.onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_owner_consent')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('buffalo_owner_consent')));
    await tester.pumpAndSettle();
    final approvedAction = tester.widget<FilledButton>(
      find.byKey(const Key('buffalo_inventory_import')),
    );
    expect(approvedAction.onPressed, isNotNull);
  });

  testWidgets('shows unknown clients and can mark one known in RAM only',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BuffaloInventoryPage()));
    await tester.enterText(
      find.byKey(const Key('buffalo_inventory_input')),
      '192.168.11.10, AA:BB:CC:DD:EE:01, FamilyPhone\n'
      '192.168.11.11, AA:BB:CC:DD:EE:02, Unknown',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_owner_consent')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('buffalo_owner_consent')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_inventory_import')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('buffalo_inventory_import')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_inventory_counts')),
      170,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('取得データ内 2台／未登録 2 台'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_known_AA:BB:CC:DD:EE:01')),
      170,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('buffalo_known_AA:BB:CC:DD:EE:01')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('buffalo_inventory_counts')),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('取得データ内 2台／未登録 1 台'), findsOneWidget);
  });
}
