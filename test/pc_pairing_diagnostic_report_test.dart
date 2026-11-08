import 'package:chappy_player/core/pc_pairing_diagnostic_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies only fixed codes, not attacker-controlled error text', () {
    const privateData = '192.168.1.42 secret-invitation=super-secret';
    final report = PcPairingDiagnosticReport.fromMessage(
      '失敗した段階 [STAGE-NET] $privateData '
      '接続確認に失敗 [PAIR-TLS] $privateData',
    );
    expect(report, isNotNull);
    expect(report, contains('STAGE-NET'));
    expect(report, contains('PAIR-TLS'));
    expect(report, isNot(contains(privateData)));
    expect(report, isNot(contains('192.168.')));
    expect(report, isNot(contains('super-secret')));
  });

  test('does not generate reports for ambiguous or unknown codes', () {
    expect(PcPairingDiagnosticReport.fromMessage('unknown exception'), isNull);
    expect(PcPairingDiagnosticReport.fromMessage(
      'STAGE-NET PAIR-TLS without brackets'), isNull);
    expect(PcPairingDiagnosticReport.fromMessage(
      '[STAGE-NET] [STAGE-KEY] [PAIR-NET]'), isNull);
    expect(PcPairingDiagnosticReport.fromMessage(
      '[STAGE-NET] [PAIR-NET] [PAIR-TLS]'), isNull);
    expect(PcPairingDiagnosticReport.fromMessage(
      '[STAGE-FAKE] [PAIR-FAKE]'), isNull);
  });
}
