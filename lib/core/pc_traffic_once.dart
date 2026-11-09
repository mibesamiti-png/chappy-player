import 'dart:convert';

import 'package:crypto/crypto.dart';

/// NETLAB-04B. Cryptographic domain separation for one approved traffic read.
/// Duration is signed along with each fresh QR-v3 challenge nonce. This is
/// only used by the trusted Flutter host, never by mini-app JavaScript.
String pcTrafficScopedNonce(String rawHex, int seconds) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHex) ||
      seconds < 5 || seconds > 30) {
    throw const FormatException('通信量取得の認証用乱数・計測時間が不正です');
  }
  final bytes = <int>[
    ...utf8.encode('CHAPPY-PC-TRAFFIC-READ-V1'),
    0,
    seconds,
    for (var i = 0; i < rawHex.length; i += 2)
      int.parse(rawHex.substring(i, i + 2), radix: 16),
  ];
  return sha256.convert(bytes).toString();
}
