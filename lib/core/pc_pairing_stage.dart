/// Safe, fixed-name stages for a one-shot PC pairing attempt.
///
/// No invitation, key, IP address or signed proof is recorded here.
/// The stage indicates the operation being attempted, NOT its root cause.
/// These values are diagnostics only and never authorize a connection.
enum PcPairingStage {
  qr('STAGE-QR', 'QR・入力内容の確認'),
  identity('STAGE-KEY', 'スマホ端末鍵の事前確認'),
  network('STAGE-NET', 'LAN・TLS接続とPC応答'),
  pcProof('STAGE-PC', 'PCの端末署名の検証'),
  phoneConsent('STAGE-PHONE', 'スマホ側の承認・署名'),
  finish('STAGE-FINISH', 'PC側の最終検証');

  const PcPairingStage(this.code, this.label);

  final String code;
  final String label;

  String get safeSummary => '失敗した段階: $label [$code]';
}
