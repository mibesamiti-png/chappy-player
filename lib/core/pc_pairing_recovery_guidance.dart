import 'package:chappy_player/core/pc_pairing_stage.dart';

/// Local, fixed-text suggestions for an explicitly failed pairing attempt.
///
/// A diagnostic stage identifies where work stopped, not the root cause.
/// Never return raw error text, endpoint data, invitation values or keys.
class PcPairingRecoveryGuidance {
  static const _knownErrors = <String>[
    'PAIR-TLS', 'PAIR-NET', 'PAIR-TIME', 'PAIR-FORMAT',
    'PAIR-HOST', 'PAIR-STATE', 'PAIR-OTHER',
  ];

  static String? fromMessage(String message) {
    final stages = PcPairingStage.values
        .where((stage) => message.contains('[${stage.code}]'))
        .toList();
    final errors = _knownErrors
        .where((code) => message.contains('[$code]'))
        .toList();
    if (stages.length != 1 || errors.length != 1) return null;

    final stage = stages.single;
    final error = errors.single;
    // Order matters: error-specific guidance is more actionable than stage.
    if (error == 'PAIR-TLS') {
      return 'PCで新しいQRを発行し、TLS指紋を画面上で照合してください。'
          '指紋の警告を無視して接続しないでください。';
    }
    if (error == 'PAIR-HOST') {
      return 'Androidアプリを前面で開き直し、端末側のPC Link機能を確認してください。'
          '必要なら新しいQRを読み直してください。';
    }
    if (stage == PcPairingStage.identity) {
      return 'スマホの端末鍵が利用可能か確認してください。'
          '鍵を初期化・削除する操作は、この案内だけで行わないでください。';
    }
    if (stage == PcPairingStage.qr || error == 'PAIR-FORMAT') {
      return 'QRの期限・接続先・指紋を確認し、PCで新しいQRを発行してください。'
          '使用済みQRは再利用できません。';
    }
    if (error == 'PAIR-NET' || error == 'PAIR-TIME') {
      return 'PC側の待受画面とファイアウォール、両端末の信頼できるLAN接続を確認し、'
          '新しいQRからやり直してください。';
    }
    if (stage == PcPairingStage.pcProof) {
      return 'PCの本人確認画面と公開鍵指紋を再確認してください。'
          '署名検証が通らない場合は承認しないでください。';
    }
    if (stage == PcPairingStage.phoneConsent) {
      return 'スマホ側で一回限りの署名承認を行ったか確認してください。'
          '拒否した場合は新しいQRから始めてください。';
    }
    if (stage == PcPairingStage.finish) {
      return 'PC側の最終承認状態を確認し、再試行する場合は新しいQRを発行してください。';
    }
    return '両端末の状態を確認し、必要なら新しいQRを発行してください。'
        '認証警告を回避する操作は行わないでください。';
  }
}
