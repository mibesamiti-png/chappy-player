import 'dart:io';

import 'package:chappy_player/core/background_audio_asset_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory packageDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chappy_background_audio_');
    packageDir = Directory(p.join(root.path, 'installed', 'current'));
    await Directory(p.join(packageDir.path, 'audio')).create(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('accepts bundled audio only', () async {
    final path = p.join(packageDir.path, 'audio', 'music.mp3');
    await File(path).writeAsBytes([0, 1, 2, 3], flush: true);
    final resolved = await resolveBundledBackgroundAudioAsset(
      packageDir, 'audio/music.mp3',
    );
    expect(await resolved.resolveSymbolicLinks(),
        await File(path).resolveSymbolicLinks());
    expect(isSafeBackgroundAudioAssetPath('audio/loop.ogg'), isTrue);
    expect(isSafeBackgroundAudioAssetPath('audio/clip.m4a'), isTrue);
    expect(isSafeBackgroundAudioAssetPath('audio/track.flac'), isTrue);
  });

  test('rejects arbitrary paths, URLs and non-audio files', () {
    for (final name in <String>[
      '', '../secret.mp3', 'audio/../secret.mp3', 'audio//song.mp3',
      '/tmp/secret.mp3', 'C:\\Users\\secret.mp3',
      'https://example.org/sound.mp3', 'content://microphone',
      'audio/song%2fsecret.mp3', 'audio/song.mp3?token=x',
      'audio/song.mp3#fragment', 'audio/.private.mp3',
      './song.mp3', 'audio/script.js', 'audio/picture.png',
    ]) {
      expect(isSafeBackgroundAudioAssetPath(name), isFalse, reason: name);
    }
  });

  test('refuses zero-length and missing assets', () async {
    await File(p.join(packageDir.path, 'audio', 'empty.wav')).create();
    expect(
      resolveBundledBackgroundAudioAsset(packageDir, 'audio/empty.wav'),
      throwsFormatException,
    );
    expect(
      resolveBundledBackgroundAudioAsset(packageDir, 'audio/missing.mp3'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('refuses symlinks, even when they point to an audio file', () async {
    final outside = File(p.join(root.path, 'secret.mp3'));
    await outside.writeAsBytes([0, 1, 2]);
    final linked = Link(p.join(packageDir.path, 'audio', 'linked.mp3'));
    await linked.create(outside.path);
    expect(
      resolveBundledBackgroundAudioAsset(packageDir, 'audio/linked.mp3'),
      throwsFormatException,
    );
  });
}
