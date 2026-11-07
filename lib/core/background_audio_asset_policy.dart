import 'dart:io';

import 'package:path/path.dart' as p;

/// Phase 1 preparation for *bundled-file-only* native background audio.
///
/// This resolver does not start a service or expose a JS API. It refuses
/// external URLs and paths outside the app's installed package directory.
const supportedBackgroundAudioExtensions = <String>{
  '.mp3', '.m4a', '.ogg', '.wav', '.flac',
};

bool isSafeBackgroundAudioAssetPath(String asset) {
  if (asset.isEmpty || asset.length > 240 ||
      asset.startsWith('/') || asset.contains('\\') ||
      asset.contains(':') || asset.contains('%') ||
      asset.contains('?') || asset.contains('#') ||
      asset.contains('\u0000') ||
      !RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(asset)) {
    return false;
  }
  if (asset.split('/').any((segment) =>
      segment.isEmpty || segment == '.' || segment == '..' ||
      segment.startsWith('.'))) {
    return false;
  }
  return supportedBackgroundAudioExtensions.contains(
    p.extension(asset).toLowerCase(),
  );
}

/// Resolve to a file within [packageDir], rejecting redirects via symlinks.
/// The package installation process itself must also reject archive symlinks.
///
/// Never accept arbitrary user-provided OS paths or network URLs here.
/// Revalidate ownership in the native service before starting playback.
Future<File> resolveBundledBackgroundAudioAsset(
  Directory packageDir,
  String asset,
) async {
  if (!isSafeBackgroundAudioAssetPath(asset)) {
    throw const FormatException('Unsupported or unsafe background audio asset path');
  }
  if (!await packageDir.exists()) {
    throw const FileSystemException('Installed app directory not found');
  }
  final base = await packageDir.resolveSymbolicLinks();
  var cursor = base;
  for (final part in asset.split('/')) {
    cursor = p.join(cursor, part);
    if (await FileSystemEntity.type(cursor, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Background audio asset cannot be a symbolic link');
    }
  }
  final file = File(cursor);
  if (!await file.exists()) {
    throw const FileSystemException('Background audio asset not found');
  }
  final realPath = await file.resolveSymbolicLinks();
  if (!p.isWithin(base, realPath)) {
    throw const FormatException('Background audio asset escaped its package');
  }
  final bytes = await file.length();
  if (bytes < 1 || bytes > 10 * 1024 * 1024) {
    throw const FormatException('Background audio asset size is invalid');
  }
  return File(realPath);
}
