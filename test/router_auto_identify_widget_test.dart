import 'package:chappy_player/core/router_identity_client.dart';
import 'package:chappy_player/screens/router_auto_identify_page.dart';
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
      expect(call.arguments, isNull);
      return <String, dynamic>{
        'gatewayIpv4': '192.168.11.1',
        'source': 'android_wifi_default_route',
        'evidence': 'upnp_self_report',
        'manufacturer': 'BUFFALO',
        'modelName': 'AirStation',
        'modelNumber': 'WSR-DEMO',
        'friendlyName': 'Router demo',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('explicit owner and per-probe approval gate all network calls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: RouterAutoIdentifyPage(client: RouterIdentityClient(channel: channel)),
    ));
    expect(calls, isEmpty);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('router_id_start')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('router_id_owner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('router_id_start')));
    await tester.pumpAndSettle();
    expect(find.text('今回だけ識別する'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.byKey(const Key('router_id_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今回だけ識別する'));
    await tester.pumpAndSettle();
    expect(calls, ['routerIdentityProbe']);
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_id_gateway')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('192.168.11.1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_id_model')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AirStation'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_id_manufacturer')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BUFFALO'), findsOneWidget);
  });

  testWidgets('clear deletes RAM-only candidate and requires new consent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: RouterAutoIdentifyPage(client: RouterIdentityClient(channel: channel)),
    ));
    await tester.tap(find.byKey(const Key('router_id_owner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('router_id_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今回だけ識別する'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_id_clear')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('router_id_clear')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_id_start')),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('router_id_start')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('router_id_model')), findsNothing);
    expect(calls, hasLength(1));
  });
}
