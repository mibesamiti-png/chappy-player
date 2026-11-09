import 'package:chappy_player/core/companion_qr_invitation.dart';
import 'package:chappy_player/core/pc_media_once.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Only four fixed media keys have labels', () {
    expect(PcMediaOnce.commands.length, 4);
    for (final cmd in PcMediaOnce.commands) {
      expect(PcMediaOnce.label(cmd), isNotEmpty);
    }
    for (final bad in <String>['', 'shell', 'keyboard', 'volume_up;cmd']) {
      expect(() => PcMediaOnce.label(bad), throwsFormatException);
    }
  });

  test('Media proof binds the exact command in a new domain', () {
    const raw = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final up = pcMediaScopedNonce(raw, 'volume_up');
    expect(up.length, 64);
    expect(up, isNot(raw));
    expect(up, isNot(pcMediaScopedNonce(raw, 'volume_down')));
    expect(() => pcMediaScopedNonce('z', 'volume_up'), throwsFormatException);
    expect(() => pcMediaScopedNonce(raw, 'arbitrary_key'), throwsFormatException);
  });

  test('Media QR-v3 flag cannot be combined or downgraded to v2', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1799999700000, isUtc: true);
    const base = 'chappy-pair://v3?ip=192.168.1.7&port=49152&fp='
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        '&inv=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&exp=1800000000'
        '&pc=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final invite = CompanionQrInvitation.parse('$base&media=1', now: now);
    expect(invite.mediaOnce, isTrue);
    expect(invite.statusOnce || invite.fileOnce || invite.uploadOnce, isFalse);
    for (final suffix in <String>[
      '&media=0', '&media=1&media=1', '&media=true',
      '&media=1&status=1', '&media=1&file=1', '&media=1&upload=1',
    ]) {
      expect(() => CompanionQrInvitation.parse('$base$suffix', now: now),
          throwsFormatException);
    }
    final v2 = base.replaceFirst('://v3', '://v2').replaceFirst(
      '&pc=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', '');
    expect(() => CompanionQrInvitation.parse('$v2&media=1', now: now),
        throwsFormatException);
  });
}
