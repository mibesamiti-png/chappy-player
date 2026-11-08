import 'package:chappy_player/core/pc_pairing_stage.dart';

/// Builds a shareable report from strict allowlisted diagnostic codes only.
///
/// The input can be an arbitrary UI/error string. Never echo it: a future
/// error path might accidentally include an endpoint, invitation or nonce.
class PcPairingDiagnosticReport {
  static const _failureCodes = <String>[
    'PAIR-TLS', 'PAIR-NET', 'PAIR-TIME', 'PAIR-FORMAT',
    'PAIR-HOST', 'PAIR-STATE', 'PAIR-OTHER',
  ];

  static String? fromMessage(String message) {
    final stages = PcPairingStage.values
        .where((stage) => message.contains('[${stage.code}]'))
        .toList();
    final failures = _failureCodes
        .where((code) => message.contains('[$code]'))
        .toList();

    // Only copy a single, unambiguous stage and error classification.
    if (stages.length != 1 || failures.length != 1) return null;
    return 'Chappy Player / PC Link\n'
        'Stage: ${stages.single.code}\n'
        'Error: ${failures.single}\n'
        'QR招待・鍵・署名・接続先・端末情報は含みません。';
  }
}
