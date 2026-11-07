import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Stable, non-sensitive diagnostics for the trusted PC pairing screen.
/// Never serialize an exception's toString(): network errors may embed
/// endpoints, paths or protocol details and must not be copied to bug reports.
class PcPairingFailure {
  final String code;
  final String guidance;

  const PcPairingFailure(this.code, this.guidance);

  String get safeMessage => '接続確認に失敗 [$code]：$guidance';

  static PcPairingFailure classify(Object error) {
    if (error is HandshakeException || error is TlsException) {
      return const PcPairingFailure(
        'PAIR-TLS', 'PCのTLS証明書・QR指紋を確認し、新しいQRからやり直してください。',
      );
    }
    if (error is SocketException) {
      return const PcPairingFailure(
        'PAIR-NET', '同じ信頼できるLANの接続状態、PC側の起動とファイアウォールを確認してください。',
      );
    }
    if (error is TimeoutException) {
      return const PcPairingFailure(
        'PAIR-TIME', '応答が間に合いませんでした。PC側の確認画面とLANを確認し、新しいQRを発行してください。',
      );
    }
    if (error is FormatException) {
      return const PcPairingFailure(
        'PAIR-FORMAT', 'QRの期限・入力内容またはPC応答形式を確認し、新しいQRからやり直してください。',
      );
    }
    if (error is PlatformException || error is MissingPluginException) {
      return const PcPairingFailure(
        'PAIR-HOST', 'Androidのホスト機能を利用できません。アプリの状態を確認してください。',
      );
    }
    if (error is StateError) {
      return const PcPairingFailure(
        'PAIR-STATE', '端末キー・相互承認・QRの有効期限を確認し、新しいQRからやり直してください。',
      );
    }
    return const PcPairingFailure(
      'PAIR-OTHER', '認証を完了できませんでした。診断記録には秘密情報を含めず、再現手順のみを控えてください。',
    );
  }
}
