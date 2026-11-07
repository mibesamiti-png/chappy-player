import 'package:chappy_player/core/pc_identity_client.dart';
import 'package:chappy_player/screens/pc_identity_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  final fingerprint = List<String>.filled(64, 'a').join();

  test('strict public identity wire parsing; never accepts private values', () {
    final empty = PcIdentityStatus.fromWire(
      <String, dynamic>{'created': false, 'algorithm': 'P-256'},
    );
    expect(empty.created, isFalse);
    expect(empty.fingerprint, isNull);
    final created = PcIdentityStatus.fromWire(<String, dynamic>{
      'created': true,
      'algorithm': 'P-256',
      'fingerprint': fingerprint,
    });
    expect(created.created, isTrue);
    expect(created.fingerprint, fingerprint);
    for (final invalid in <Map<String, dynamic>>[
      {'created': true, 'algorithm': 'P-256'},
      {'created': false, 'algorithm': 'P-256', 'fingerprint': fingerprint},
      {'created': true, 'algorithm': 'Ed25519', 'fingerprint': fingerprint},
      {'created': true, 'algorithm': 'P-256', 'fingerprint': 'abc'},
    ]) {
      expect(() => PcIdentityStatus.fromWire(invalid), throwsFormatException);
    }
  });

  test('revoke client rejects invalid fingerprints before native call',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (method) async {
      calls.add(method.method);
      throw StateError('No native operation is expected');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const client = PcIdentityClient(channel: channel);
    for (final invalid in <String>[
      '', 'abc', List<String>.filled(64, 'A').join(),
      List<String>.filled(63, 'a').join(),
    ]) {
      await expectLater(client.revoke(invalid), throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  testWidgets('partial revoke failure refreshes the actual identity state',
      (tester) async {
    var exists = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (method) async {
      calls.add(method.method);
      if (method.method == 'pcIdentityStatus') {
        return <String, Object>{
          'created': exists, 'algorithm': 'P-256',
          if (exists) 'fingerprint': fingerprint,
        };
      }
      if (method.method == 'pcIdentityRevoke') {
        expect(method.arguments,
            <String, String>{'fingerprint': fingerprint});
        exists = false;
        throw PlatformException(code: 'HISTORY_CLEAN_FAILED');
      }
      throw StateError('Unexpected host method');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(const MaterialApp(home: PcIdentityPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pc_identity_revoke')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pc_identity_revoke_suffix')),
      fingerprint.substring(56),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('pc_identity_revoke_confirm')));
    await tester.pumpAndSettle();

    expect(calls, <String>[
      'pcIdentityStatus', 'pcIdentityRevoke', 'pcIdentityStatus',
    ]);
    expect(find.text('Android端末キー：未作成'), findsOneWidget);
    expect(find.byKey(const Key('pc_identity_fingerprint')), findsNothing);
    expect(find.byKey(const Key('pc_identity_error')), findsOneWidget);
  });

  testWidgets('key is never generated without explicit on-screen approval',
      (tester) async {
    final calls = <String>[];
    var created = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (method) async {
      calls.add(method.method);
      if (method.method == 'pcIdentityStatus') {
        return <String, Object>{
          'created': created,
          'algorithm': 'P-256',
          if (created) 'fingerprint': fingerprint,
        };
      }
      if (method.method == 'pcIdentityCreate') {
        created = true;
        return <String, Object>{
          'created': true, 'algorithm': 'P-256',
          'fingerprint': fingerprint,
        };
      }
      if (method.method == 'pcIdentityRevoke') {
        expect(method.arguments,
            <String, String>{'fingerprint': fingerprint});
        created = false;
        return true;
      }
      throw UnimplementedError(method.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const MaterialApp(home: PcIdentityPage()));
    await tester.pumpAndSettle();
    expect(find.text('Android端末キー：未作成'), findsOneWidget);
    expect(calls, <String>['pcIdentityStatus']);
    expect(find.byKey(const Key('pc_identity_fingerprint')), findsNothing);

    // Cancel first: no Android create method is ever invoked.
    await tester.tap(find.byKey(const Key('pc_identity_create')));
    await tester.pumpAndSettle();
    expect(find.text('この端末の接続用キーを作成'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, <String>['pcIdentityStatus']);

    await tester.tap(find.byKey(const Key('pc_identity_create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('端末キーを作成').last);
    await tester.pumpAndSettle();
    expect(calls, <String>['pcIdentityStatus', 'pcIdentityCreate']);
    expect(find.byKey(const Key('pc_identity_fingerprint')), findsOneWidget);
    expect(find.text('Android端末キー：作成済み'), findsOneWidget);

    // Delete is a separate, explicit decision.
    await tester.tap(find.byKey(const Key('pc_identity_revoke')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除しない'));
    await tester.pumpAndSettle();
    expect(calls.contains('pcIdentityRevoke'), isFalse);
    await tester.tap(find.byKey(const Key('pc_identity_revoke')));
    await tester.pumpAndSettle();
    var delete = tester.widget<FilledButton>(
      find.byKey(const Key('pc_identity_revoke_confirm')),
    );
    expect(delete.onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('pc_identity_revoke_suffix')), 'WRONG123',
    );
    await tester.pump();
    delete = tester.widget<FilledButton>(
      find.byKey(const Key('pc_identity_revoke_confirm')),
    );
    expect(delete.onPressed, isNull);
    expect(calls.contains('pcIdentityRevoke'), isFalse);
    await tester.enterText(
      find.byKey(const Key('pc_identity_revoke_suffix')),
      fingerprint.substring(56),
    );
    await tester.pump();
    delete = tester.widget<FilledButton>(
      find.byKey(const Key('pc_identity_revoke_confirm')),
    );
    expect(delete.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('pc_identity_revoke_confirm')));
    await tester.pumpAndSettle();
    expect(calls, <String>[
      'pcIdentityStatus', 'pcIdentityCreate', 'pcIdentityRevoke',
      'pcIdentityStatus',
    ]);
    expect(find.text('Android端末キー：未作成'), findsOneWidget);
    expect(find.byKey(const Key('pc_identity_fingerprint')), findsNothing);
  });
}
