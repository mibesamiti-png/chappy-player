import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Fixed one-command media capability. No arbitrary Windows key or shell.
abstract final class PcMediaOnce {
  static const protocol = 'pc-media-once-v1';
  static const commands = <String>[
    'volume_up', 'volume_down', 'toggle_mute', 'play_pause',
  ];

  static String label(String command) => switch (command) {
    'volume_up' => '音量を上げる',
    'volume_down' => '音量を下げる',
    'toggle_mute' => 'ミュート切替',
    'play_pause' => '再生／一時停止',
    _ => throw const FormatException('メディア操作が許可されていません'),
  };
}

String pcMediaScopedNonce(String rawHex, String command) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHex) ||
      !PcMediaOnce.commands.contains(command)) {
    throw const FormatException('メディア操作の署名対象が不正です');
  }
  final bytes = <int>[
    ...utf8.encode('CHAPPY-PC-MEDIA-CONTROL-V1'),
    0,
    ...ascii.encode(command),
    0,
    for (var i = 0; i < rawHex.length; i += 2)
      int.parse(rawHex.substring(i, i + 2), radix: 16),
  ];
  return sha256.convert(bytes).toString();
}
