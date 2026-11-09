import 'dart:typed_data';

import 'package:chappy_player/screens/traffic_inspection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PCAP cannot load without owner and per-action consent',
      (tester) async {
    var picks = 0;
    await tester.pumpWidget(MaterialApp(home: TrafficInspectionPage(
      pickCapture: () async {
        picks++;
        return Uint8List.fromList([
          0xd4, 0xc3, 0xb2, 0xa1, 2, 0, 4, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0, 101, 0, 0, 0,
        ]);
      },
    )));
    expect(picks, 0);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('traffic_inspect_import')),
      ).onPressed, isNull,
    );
    await tester.tap(find.byKey(const Key('traffic_inspect_owner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('traffic_inspect_import')));
    await tester.pumpAndSettle();
    expect(picks, 0);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(picks, 0);

    await tester.tap(find.byKey(const Key('traffic_inspect_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('traffic_inspect_approve')));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('解析 0パケット／表示 0件'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('traffic_inspect_clear')),
      -130,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('traffic_inspect_clear')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('traffic_inspect_import')),
      -140,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('traffic_inspect_import')),
      ).onPressed, isNull,
    );
    expect(find.byKey(const Key('traffic_inspect_count')), findsNothing);
  });
}
