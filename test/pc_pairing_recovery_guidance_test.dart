import 'package:chappy_player/core/pc_pairing_recovery_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known stage/error pairs produce fixed recovery instructions', () {
    const cases = <String, String>{
      '[STAGE-QR] [PAIR-FORMAT]': 'QR',
      '[STAGE-KEY] [PAIR-STATE]': '端末鍵',
      '[STAGE-NET] [PAIR-TIME]': 'LAN',
      '[STAGE-PC] [PAIR-STATE]': '公開鍵指紋',
      '[STAGE-PHONE] [PAIR-STATE]': '署名承認',
      '[STAGE-FINISH] [PAIR-STATE]': '最終承認',
      '[STAGE-NET] [PAIR-TLS]': 'TLS指紋',
      '[STAGE-KEY] [PAIR-HOST]': 'Androidアプリ',
    };
    for (final entry in cases.entries) {
      expect(
        PcPairingRecoveryGuidance.fromMessage(entry.key),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('untrusted raw error details never enter the recovery hint', () {
    const secret = 'local-ip=192.168.1.42 invitation=secret-private-token';
    final hint = PcPairingRecoveryGuidance.fromMessage(
      '[STAGE-NET] [PAIR-TLS] $secret',
    );
    expect(hint, isNotNull);
    expect(hint, isNot(contains(secret)));
    expect(hint, isNot(contains('192.168.')));
    expect(hint, isNot(contains('secret-private-token')));
  });

  test('missing and ambiguous codes do not provide guesses', () {
    expect(PcPairingRecoveryGuidance.fromMessage('unknown'), isNull);
    expect(PcPairingRecoveryGuidance.fromMessage(
      '[STAGE-QR] [STAGE-NET] [PAIR-NET]'), isNull);
    expect(PcPairingRecoveryGuidance.fromMessage(
      '[STAGE-NET] [PAIR-TLS] [PAIR-NET]'), isNull);
    expect(PcPairingRecoveryGuidance.fromMessage(
      '[STAGE-UNKNOWN] [PAIR-OTHER]'), isNull);
  });
}
