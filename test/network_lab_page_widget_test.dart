import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/screens/network_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        expect(call.arguments, <String, dynamic>{
          'serviceType': '_http._tcp.',
        });
      }
      return <String, dynamic>{
        'running': call.method != 'stop',
        'serviceType': '_http._tcp.',
        'remainingSeconds': call.method == 'stop' ? 0 : 15,
        'services': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '_http._tcp.|my-device',
            'name': 'my-device',
            'type': '_http._tcp.',
            'address': '192.168.1.10',
            'port': 8080,
            'resolved': true,
          },
        ],
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('typed client rejects unknown DNS-SD types without calling Android',
      () async {
    const client = LanDiscoveryClient(channel: channel);
    expect(
      () => client.start('_arbitrary._tcp.'),
      throwsA(isA<FormatException>()),
    );
    expect(calls, isEmpty);
    final snapshot = await client.snapshot();
    expect(snapshot.services.single.name, 'my-device');
    expect(snapshot.services.single.address, '192.168.1.10');
    expect(snapshot.services.single.port, 8080);
  });

  testWidgets('explicit confirmation is required before any discovery',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: NetworkLabPage(client: LanDiscoveryClient(channel: channel)),
    ));
    expect(calls, isEmpty);
    expect(find.text('探索停止中'), findsOneWidget);

    await tester.tap(find.byKey(const Key('netlab_start')));
    await tester.pumpAndSettle();
    expect(find.text('15秒間だけ探す'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.byKey(const Key('netlab_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15秒間だけ探す'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.where((call) => call == 'start').length, 1);
    expect(find.text('my-device'), findsOneWidget);
    expect(find.textContaining('192.168.1.10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('netlab_stop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.contains('stop'), isTrue);
    expect(find.text('探索停止中'), findsOneWidget);
  });
}
