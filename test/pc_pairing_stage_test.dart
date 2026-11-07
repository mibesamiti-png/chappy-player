import 'package:chappy_player/core/pc_pairing_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every stage has a unique stable code and fixed safe summary', () {
    expect(PcPairingStage.values.length, 5);
    expect(PcPairingStage.values.map((stage) => stage.code).toSet().length, 5);
    for (final stage in PcPairingStage.values) {
      expect(stage.code, startsWith('STAGE-'));
      expect(stage.safeSummary, contains(stage.code));
      expect(stage.safeSummary, isNot(contains('192.168.')));
      expect(stage.safeSummary, isNot(contains('nonce')));
      expect(stage.safeSummary, isNot(contains('invitation')));
    }
  });

  test('QR-v3 progression names remain distinct', () {
    expect(PcPairingStage.qr.code, 'STAGE-QR');
    expect(PcPairingStage.network.code, 'STAGE-NET');
    expect(PcPairingStage.pcProof.code, 'STAGE-PC');
    expect(PcPairingStage.phoneConsent.code, 'STAGE-PHONE');
    expect(PcPairingStage.finish.code, 'STAGE-FINISH');
  });
}
