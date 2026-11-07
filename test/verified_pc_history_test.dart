import 'package:chappy_player/core/verified_pc_history_client.dart';
import 'package:chappy_player/screens/verified_pc_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.chappy.player/network_lab');
  final fpA = List<String>.filled(64, 'a').join();
  final fpB = List<String>.filled(64, 'b').join();

  test('only valid bounded public fingerprints and timestamps are parsed', () {
    final data = VerifiedPcRecord.fromWire(
      <String, Object>{'fingerprint': fpA, 'added': 2000000000},
    );
    expect(data.fingerprint, fpA);
    expect(data.addedUnix, 2000000000);
    for (final wrong in <Map<String, dynamic>>[
      <String, dynamic>{'fingerprint': 'abc', 'added': 1},
      <String, dynamic>{'fingerprint': fpA.toUpperCase(), 'added': 1},
      <String, dynamic>{'fingerprint': fpA, 'added': -1},
      <String, dynamic>{'fingerprint': fpA, 'added': 0},
      <String, dynamic>{
        'fingerprint': fpA, 'added': 1, 'privateKey': 'must never exist',
      },
    ]) {
      expect(() => VerifiedPcRecord.fromWire(wrong), throwsFormatException);
    }
  });

  test('history list does not write; malformed and duplicated entries fail',
      () async {
    final calls = <String>[];
    var duplicate = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcList') {
        final records = <Map<String, Object>>[
          <String, Object>{'fingerprint': fpA, 'added': 2000000000},
        ];
        if (duplicate) records.add(records.first);
        return records;
      }
      throw UnimplementedError(call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const client = VerifiedPcHistoryClient(channel: channel);
    final entries = await client.list();
    expect(entries.single.fingerprint, fpA);
    expect(calls, <String>['verifiedPcList']);
    duplicate = true;
    await expectLater(client.list(), throwsFormatException);
    await expectLater(client.remember('wrong'), throwsFormatException);
    expect(calls, <String>['verifiedPcList', 'verifiedPcList']);
  });

  testWidgets('history deletion needs dialog consent, no automatic writes',
      (tester) async {
    final calls = <String>[];
    final stored = <String>{fpA, fpB};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcList' ||
          call.method == 'verifiedPcForget') {
        if (call.method == 'verifiedPcForget') {
          stored.remove(call.arguments['fingerprint'] as String);
        }
        return stored.map((fp) => <String, Object>{
          'fingerprint': fp,
          'added': 2000000000,
        }).toList();
      }
      throw UnimplementedError(call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      home: VerifiedPcHistoryPage(
        client: VerifiedPcHistoryClient(channel: channel),
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList']);
    expect(find.byKey(Key('verified_pc_$fpA')), findsOneWidget);
    expect(find.byKey(Key('verified_pc_$fpB')), findsOneWidget);

    await tester.tap(find.text('記録を削除').first);
    await tester.pumpAndSettle();
    expect(find.text('PCの確認履歴を削除'), findsOneWidget);
    await tester.tap(find.text('削除しない'));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList']);
    expect(stored.length, 2);

    await tester.tap(find.text('記録を削除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('この記録を削除'));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList', 'verifiedPcForget']);
    expect(stored.length, 1);
  });

  testWidgets('clear all is separately confirmed and preserves other features',
      (tester) async {
    final calls = <String>[];
    final stored = <String>{fpA, fpB};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcClear') {
        expect(call.arguments, isNull);
        stored.clear();
      } else if (call.method != 'verifiedPcList') {
        throw UnimplementedError(call.method);
      }
      return stored.map((fp) => <String, Object>{
        'fingerprint': fp,
        'added': 2000000000,
      }).toList();
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      home: VerifiedPcHistoryPage(
        client: VerifiedPcHistoryClient(channel: channel),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verified_pc_clear_all')), findsOneWidget);
    expect(calls, <String>['verifiedPcList']);

    await tester.tap(find.byKey(const Key('verified_pc_clear_all')));
    await tester.pumpAndSettle();
    expect(find.text('すべてのPC確認履歴を削除'), findsOneWidget);
    await tester.tap(find.text('削除しない'));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList']);
    expect(stored.length, 2);

    await tester.tap(find.byKey(const Key('verified_pc_clear_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verified_pc_clear_confirm')));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList', 'verifiedPcClear']);
    expect(stored, isEmpty);
    expect(find.byKey(const Key('verified_pc_empty')), findsOneWidget);
    expect(find.byKey(const Key('verified_pc_clear_all')), findsNothing);
  });

  testWidgets('corrupt encrypted history can be reset without reading it',
      (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcList') {
        throw PlatformException(code: 'NETLAB_PC_HISTORY_FAILED');
      }
      if (call.method == 'verifiedPcClear') {
        return <Map<String, Object>>[];
      }
      throw UnimplementedError(call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      home: VerifiedPcHistoryPage(
        client: VerifiedPcHistoryClient(channel: channel),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verified_pc_error')), findsOneWidget);
    expect(find.byKey(const Key('verified_pc_clear_all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('verified_pc_clear_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verified_pc_clear_confirm')));
    await tester.pumpAndSettle();
    expect(calls, <String>['verifiedPcList', 'verifiedPcClear']);
    expect(find.byKey(const Key('verified_pc_empty')), findsOneWidget);
  });

  testWidgets('initial empty history is read-only', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return <Map<String, Object>>[];
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      home: VerifiedPcHistoryPage(
        client: VerifiedPcHistoryClient(channel: channel),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verified_pc_empty')), findsOneWidget);
    expect(calls, <String>['verifiedPcList']);
  });
}
