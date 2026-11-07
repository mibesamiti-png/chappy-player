import 'dart:async';
import 'dart:io';

import 'package:chappy_player/core/pc_pairing_failure.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps transport and validation failures to stable diagnostic codes', () {
    expect(PcPairingFailure.classify(
      const SocketException('host=192.168.1.8 secret=abc'),
    ).code, 'PAIR-NET');
    expect(PcPairingFailure.classify(
      TimeoutException('private invitation=do-not-print'),
    ).code, 'PAIR-TIME');
    expect(PcPairingFailure.classify(
      HandshakeException('private certificate details'),
    ).code, 'PAIR-TLS');
    expect(PcPairingFailure.classify(
      const FormatException('invite=private'),
    ).code, 'PAIR-FORMAT');
    expect(PcPairingFailure.classify(
      PlatformException(code: 'private-host-code', message: 'sensitive'),
    ).code, 'PAIR-HOST');
    expect(PcPairingFailure.classify(
      StateError('phone nonce=private'),
    ).code, 'PAIR-STATE');
  });

  test('never formats raw errors in user-facing messages', () {
    const secret = 'secret-qr-invitation-should-not-leak';
    final samples = <Object>[
      const SocketException(secret),
      TimeoutException(secret),
      HandshakeException(secret),
      const FormatException(secret),
      PlatformException(code: secret, message: secret),
      StateError(secret),
      Exception(secret),
    ];
    for (final sample in samples) {
      final message = PcPairingFailure.classify(sample).safeMessage;
      expect(message, isNot(contains(secret)));
      expect(message, contains('PAIR-'));
    }
    expect(PcPairingFailure.classify(Exception(secret)).code, 'PAIR-OTHER');
  });
}
