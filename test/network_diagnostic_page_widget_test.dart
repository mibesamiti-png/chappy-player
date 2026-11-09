import 'dart:async';

import 'package:chappy_player/core/network_diagnostic_service.dart';
import 'package:chappy_player/screens/network_diagnostic_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('diagnosis never starts before explicit dialog approval',
      (tester) async {
    final calls = <String>[];
    NetworkDiagnosticService fake() => NetworkDiagnosticService(
      interfaceProbe: () async {
        calls.add('interface');
        return 1;
      },
      dnsProbe: () async {
        calls.add('dns');
        return true;
      },
      httpsProbe: () async {
        calls.add('https');
        return 204;
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: NetworkDiagnosticPage(serviceFactory: fake),
    ));
    expect(calls, isEmpty);

    await tester.tap(find.byKey(const Key('r7_diag_start')));
    await tester.pumpAndSettle();
    expect(find.text('今回だけ診断する'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.byKey(const Key('r7_diag_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今回だけ診断する'));
    await tester.pumpAndSettle();
    expect(calls, ['interface', 'dns', 'https']);
    expect(find.byKey(const Key('r7_diag_https')), findsOneWidget);
    expect(find.text('HTTP 204'), findsOneWidget);
  });

  testWidgets('cancel discards in-flight result and has no automatic retry',
      (tester) async {
    final pending = Completer<int>();
    var runs = 0;
    await tester.pumpWidget(MaterialApp(
      home: NetworkDiagnosticPage(
        serviceFactory: () => NetworkDiagnosticService(
          interfaceProbe: () {
            runs++;
            return pending.future;
          },
          dnsProbe: () async => throw StateError('should not run'),
          httpsProbe: () async => throw StateError('should not run'),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('r7_diag_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今回だけ診断する'));
    await tester.pump();
    expect(runs, 1);
    expect(find.byKey(const Key('r7_diag_stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('r7_diag_stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('r7_diag_dns')), findsNothing);
    expect(find.textContaining('中止'), findsWidgets);
    pending.complete(1);
    await tester.pumpAndSettle();
    expect(runs, 1);
    expect(find.byKey(const Key('r7_diag_https')), findsNothing);
  });
}
