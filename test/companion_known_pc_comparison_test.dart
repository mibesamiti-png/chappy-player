import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/core/verified_pc_history_client.dart';
import 'package:chappy_player/screens/companion_pairing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.chappy.player/network_lab');
  const service = LanDiscoveredService(
    id: '_workstation._tcp.|PC',
    name: 'Previously verified PC',
    type: '_workstation._tcp.',
    address: '192.168.1.7',
    port: 49152,
    resolved: true,
  );
  final savedFp = List<String>.filled(64, 'c').join();
  final otherFp = List<String>.filled(64, 'd').join();
  final tlsFp = List<String>.filled(64, 'a').join();
  final invitation = List<String>.filled(32, 'b').join();
  final calls = <String>[];

  CompanionQrInvitation qr(String? pcFp) => CompanionQrInvitation(
        ip: service.address,
        port: service.port,
        fingerprint: tlsFp,
        invitation: invitation,
        expiresUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
        pcIdentityFingerprint: pcFp,
      );

  Widget page(Future<CompanionQrInvitation?> Function(BuildContext) reader) =>
      MaterialApp(
        home: CompanionPairingPage(
          service: service,
          discoveryClient: const LanDiscoveryClient(channel: channel),
          historyClient: const VerifiedPcHistoryClient(channel: channel),
          qrReader: reader,
        ),
      );

  Future<void> selectSaved(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('pair_choose_known_pc')));
    await tester.tap(find.byKey(const Key('pair_choose_known_pc')));
    await tester.pumpAndSettle();
    expect(find.text('比較するPCの公開鍵指紋を選択'), findsOneWidget);
    await tester.tap(find.byKey(Key('pair_choose_fp_' + savedFp)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_expected_pc_fingerprint')),
        findsOneWidget);
  }

  Future<void> scan(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('pair_scan_qr')));
    await tester.tap(find.byKey(const Key('pair_scan_qr')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcList') {
        return <Map<String, Object>>[
          <String, Object>{'fingerprint': savedFp, 'added': 2000000000},
        ];
      }
      throw StateError('Unexpected network or history write: ' + call.method);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('matching previously verified PC does not authorize pairing',
      (tester) async {
    await tester.pumpWidget(page((_) async => qr(savedFp)));
    await selectSaved(tester);
    await scan(tester);
    expect(find.byKey(const Key('pair_known_pc_matched')), findsOneWidget);
    expect(find.byKey(const Key('pair_qr_mode')), findsOneWidget);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    expect(find.byKey(const Key('pair_save_verified_pc')), findsNothing);
    expect(calls, <String>['verifiedPcList']);
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    ).onPressed, isNotNull);
  });

  testWidgets('changed key rejects QR before networking; clearing does not reuse it',
      (tester) async {
    var scans = 0;
    await tester.pumpWidget(page((_) async {
      scans++;
      return qr(otherFp);
    }));
    await selectSaved(tester);
    await scan(tester);
    expect(scans, 1);
    expect(find.byKey(const Key('pair_known_pc_matched')), findsNothing);
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    expect(tester.widget<TextField>(
      find.byKey(const Key('pair_fingerprint')),
    ).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    ).onPressed, isNull);
    expect(calls, <String>['verifiedPcList']);

    await tester.ensureVisible(find.byKey(const Key('pair_clear_known_pc')));
    await tester.tap(find.byKey(const Key('pair_clear_known_pc')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_expected_pc_fingerprint')), findsNothing);
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    expect(scans, 1);
    expect(calls, <String>['verifiedPcList']);
  });

  testWidgets('manual fingerprint cannot bypass selected key or downgrade to QR-v2',
      (tester) async {
    await tester.pumpWidget(page((_) async => qr(null)));
    await selectSaved(tester);
    await scan(tester);
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    expect(find.byKey(const Key('pair_qr_mode')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('pair_fingerprint')), tlsFp,
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('pair_confirm')),
    ).onPressed, isNull);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    expect(calls, <String>['verifiedPcList']);
  });

  testWidgets('cancelled selection cannot silently pin a PC',
      (tester) async {
    await tester.pumpWidget(page((_) async => qr(otherFp)));
    await tester.tap(find.byKey(const Key('pair_choose_known_pc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('比較しない'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_expected_pc_fingerprint')), findsNothing);
    await scan(tester);
    expect(find.byKey(const Key('pair_qr_mode')), findsOneWidget);
    expect(find.byKey(const Key('pair_verified')), findsNothing);
    expect(calls, <String>['verifiedPcList']);
  });

  testWidgets('corrupt encrypted history never invents a saved key match',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'verifiedPcList') {
        throw PlatformException(code: 'NETLAB_PC_HISTORY_FAILED');
      }
      throw StateError('Unexpected network access');
    });
    await tester.pumpWidget(page((_) async => qr(savedFp)));
    await tester.tap(find.byKey(const Key('pair_choose_known_pc')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pair_error')), findsOneWidget);
    expect(find.byKey(const Key('pair_expected_pc_fingerprint')), findsNothing);
    expect(find.byKey(const Key('pair_known_pc_matched')), findsNothing);
    expect(calls, <String>['verifiedPcList']);
  });
}
