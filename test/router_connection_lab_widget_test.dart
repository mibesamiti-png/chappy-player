import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/screens/network_lab_page.dart';
import 'package:chappy_player/screens/router_connection_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.chappy.player/network_lab');
  var methodCalls = <String>[];

  setUp(() {
    methodCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call.method);
      if (call.method == 'stop') {
        return <String, dynamic>{
          'running': false, 'serviceType': '_http._tcp.',
          'remainingSeconds': 0,
          'services': <Map<String, Object?>>[],
        };
      }
      return false; // Safe default: no real network in widget test.
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('router read requires authorization and credentials',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: RouterConnectionLabPage(
        wifiClient: LanDiscoveryClient(channel: channel),
      ),
    ));
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile), 300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_once_read')), 300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('router_once_read')), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('router_once_read')));
    expect(button.onPressed, isNull);
    expect(methodCalls, isEmpty);

    final approve = find.byType(CheckboxListTile);
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('router_once_read')));
    await tester.tap(find.byKey(const Key('router_once_read')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_error')), 180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('router_error')), findsOneWidget);
    expect(methodCalls, isEmpty);
    expect(find.byKey(const Key('router_device_title')), findsNothing);
  });

  testWidgets('Network Lab opens separate host-only router page',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: NetworkLabPage(
        client: LanDiscoveryClient(channel: channel),
      ),
    ));
    final link = find.byKey(const Key('netlab_router_connections'));
    await tester.scrollUntilVisible(
      link, 300, scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Router Connection Lab'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('router_once_read')), 250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('router_once_read')), findsOneWidget);
    expect(methodCalls, contains('stop'));
    expect(methodCalls, isNot(contains('trafficPairingAllowed')));
  });
}
