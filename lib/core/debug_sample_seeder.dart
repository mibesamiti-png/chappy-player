import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/package_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Initial data for the isolated debug APK, never used in release/profile.
///
/// The CI debug builder creates these offline assets only in the temporary
/// debug checkout. The normal signed-release workflow never bundles them.
/// Seeding is once per version, never overwrites existing user-installed apps,
/// and is safe to retry after an interrupted installation.
class DebugSampleSeeder {
  static const manifestAsset = 'debug_sample_assets/index.json';
  final AssetBundle bundle;
  const DebugSampleSeeder({this.bundle = rootBundle});

  Future<DebugSeedReport> seed(PackageRepository repository) async {
    final raw = await bundle.loadString(manifestAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['entries'] is! List ||
        decoded['seedVersion'] is! String) {
      throw const FormatException('デバッグ用ミニアプリ一覧が不正です');
    }
    final version = decoded['seedVersion'] as String;
    if (!RegExp(r'^v[1-9][0-9]{0,5}$').hasMatch(version)) {
      throw const FormatException('デバッグ用サンプルのバージョンが不正です');
    }
    final marker = File(p.join(repository.root.path, 'debug_samples_$version.json'));
    if (await marker.exists()) {
      return const DebugSeedReport(installed: 0, skipped: 0, alreadySeeded: true);
    }

    final items = decoded['entries'] as List;
    if (items.isEmpty || items.length > 20) {
      throw const FormatException('デバッグ用サンプル数の制限を超えました');
    }
    var installed = 0;
    var skipped = 0;
    final ids = <String>{};
    final paths = <String>{};
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('デバッグ用サンプル情報が不正です');
      }
      final id = item['id'];
      final asset = item['asset'];
      final size = item['sizeBytes'];
      final hash = item['sha256'];
      if (id is! String ||
          !RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$')
              .hasMatch(id) ||
          asset is! String ||
          !RegExp(r'^debug_sample_assets/[a-z_]+\.chappy$')
              .hasMatch(asset) ||
          size is! int ||
          size < 100 ||
          size > 12 * 1024 * 1024 ||
          hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          !ids.add(id) ||
          !paths.add(asset)) {
        throw const FormatException('デバッグ用サンプル一覧の整合性エラー');
      }
      // A manually installed or modified copy always wins. Never replace
      // it, downgrade it or modify its saved private data.
      if (repository.hasApp(id)) {
        skipped++;
        continue;
      }
      final data = await bundle.load(asset);
      final bytes = Uint8List.sublistView(data);
      if (bytes.length != size ||
          sha256.convert(bytes).toString() != hash) {
        throw FormatException('デバッグ用サンプルのハッシュ不一致: $id');
      }
      final package = repository.inspect(bytes);
      if (package.id != id) {
        throw FormatException('デバッグ用サンプルIDが一致しません: $id');
      }
      await repository.install(bytes);
      installed++;
    }

    await marker.writeAsString(
      jsonEncode(<String, Object>{
        'seedVersion': version,
        'installedCount': installed,
        'skippedCount': skipped,
      }),
      flush: true,
    );
    return DebugSeedReport(installed: installed, skipped: skipped);
  }
}

class DebugSeedReport {
  final int installed;
  final int skipped;
  final bool alreadySeeded;
  const DebugSeedReport({
    required this.installed,
    required this.skipped,
    this.alreadySeeded = false,
  });
}
