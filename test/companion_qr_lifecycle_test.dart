import 'dart:async';

import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/screens/companion_pairing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.chappy.player/network_lab');
  const service = LanDiscoveredService(
    id: '_workstation._tcp.|Chappy PC test',
    name: 'Chappy PC test',
    type: '_workstation._tcp.',
    address: '192.168.1.7',
    port: 49152,
    resolved: true,
  );

  CompanionQrInvitation invitation({String ip = '192.168.1.7'}) =>
      CompanionQrInvitation(
        ip: ip,
        port: 49152,
        fingerprint: List<String>.filled(64, 'a').join(),
        invitation: List<String>.filled(32, 'b').join(),
        expiresUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
        pcIdentityFingerprint: List<String>.filled(64, 'c').join(),
      );

  Widget page(Future<CompanionQrInvitation?> Function(BuildContext) reader) =>
      MaterialApp(
        home: CompanionPairingPage(
          service: service,
          discoveryClient: const LanDiscoveryClient(channel: channel),
          qrReader: reader,
        ),
      );

  Future<void> scan(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('pair_scan_qr')));
    await tester.tap(find.byKey(const Key('pair_scan_qr')));
    await tester.pumpAndSettle();
  }

  testWidgets('QR-v3 is cleared and cannot be reused after backgrounding',
      (tester) async {
    await tester.pumpWidget(page((_) async => invitation()));
    await scan(tester);
    expect(find.byKey(const Key('pair_qr_mode')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('pair_fingerprint')),
    );
    expect(field.controller!.text, List<String>.filled(64, 'a').join());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(field.controller!.text, isEmpty);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    expect(find.byKey(const Key('pair_save_verified_pc')), findsNothing);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('QR scanned before pause cannot reappear when scan completes',
      (tester) async {
    final delayed = Completer<CompanionQrInvitation?>();
    await tester.pumpWidget(page((_) => delayed.future));
    await tester.ensureVisible(find.byKey(const Key('pair_scan_qr')));
    await tester.tap(find.byKey(const Key('pair_scan_qr')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    delayed.complete(invitation());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(tester.widget<TextField>(
      find.byKey(const Key('pair_fingerprint')),
    ).controller!.text, isEmpty);
    // Flutter resumes from pause through hidden -> inactive -> resumed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('single-use QR remains consumed after denied LAN eligibility',
      (tester) async {
    var approvalChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pairingAllowed') {
        approvalChecks++;
        return false;
      }
      throw StateError('No other host operation should be attempted');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(page((_) async => invitation()));
    await scan(tester);
    await tester.ensureVisible(find.byKey(const Key('pair_confirm')));
    await tester.tap(find.byKey(const Key('pair_confirm')));
    await tester.pumpAndSettle();
    expect(approvalChecks, 1);
    expect(find.byKey(const Key('pair_qr_consumed')), findsOneWidget);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.byKey(const Key('pair_save_verified_pc')), findsNothing);

    // Fresh PC QR is a separate explicit user action, not a silent retry.
    await scan(tester);
    expect(find.byKey(const Key('pair_qr_consumed')), findsNothing);
    final fresh = tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    );
    expect(fresh.onPressed, isNotNull);
    expect(approvalChecks, 1);
  });

  testWidgets('QR endpoint mismatch fails without retaining old scan',
      (tester) async {
    await tester.pumpWidget(page((_) async =>
        invitation(ip: '192.168.1.8')));
    await scan(tester);
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    expect(tester.widget<TextField>(
      find.byKey(const Key('pair_fingerprint')),
    ).controller!.text, isEmpty);
  });

  testWidgets('manual fingerprint edit invalidates scanned QR-v3 mode',
      (tester) async {
    await tester.pumpWidget(page((_) async => invitation()));
    await scan(tester);
    await tester.enterText(
      find.byKey(const Key('pair_fingerprint')), List<String>.filled(64, 'd').join(),
    );
    await tester.pump();
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(find.byKey(const Key('pair_save_verified_pc')), findsNothing);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
  });

  testWidgets('native LAN errors are redacted and QR remains consumed',
      (tester) async {
    const sensitive = 'private-invitation-and-local-endpoint';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pairingAllowed') {
        throw PlatformException(code: sensitive, message: sensitive);
      }
      throw StateError('Unexpected host call');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(page((_) async => invitation()));
    await scan(tester);
    await tester.ensureVisible(find.byKey(const Key('pair_confirm')));
    await tester.tap(find.byKey(const Key('pair_confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('PAIR-HOST'), findsOneWidget);
    expect(find.textContaining('STAGE-QR'), findsOneWidget);
    expect(find.textContaining(sensitive), findsNothing);
    expect(find.byKey(const Key('pair_qr_consumed')), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    ).onPressed, isNull);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
  });

}
