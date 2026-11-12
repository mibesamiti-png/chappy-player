import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/update_service.dart';

/// Public GitHub Releases list: read-only, no token or private source access.
const chappyApkHistoryApi =
    'https://api.github.com/repos/mibesamiti-png/'
    'chappy-player-updates/releases?per_page=12';

class ApkReleaseHistoryService {
  final bool debug;
  const ApkReleaseHistoryService({this.debug = false});

  /// Parse GitHub's public Release API, not arbitrary third-party feeds.
  /// A selectable APK must have a GitHub-published SHA-256 and exact download
  /// URL and versionCode matching the official release tag.
  List<UpdateRelease> parse(String source) {
    final raw = jsonDecode(source);
    if (raw is! List || raw.length > 12) {
      throw const FormatException('GitHubのリリース履歴が不正です');
    }
    final releases = <UpdateRelease>[];
    final seen = <String>{};
    final tagPattern = RegExp(debug
        ? r'^debug-v(\d+\.\d+\.\d+)-b(\d+)$'
        : r'^v(\d+\.\d+\.\d+)-b(\d+)$');
    const offsets = {
      'armeabi-v7a': 1000, 'arm64-v8a': 2000, 'x86_64': 4000,
    };
    for (final release in raw) {
      if (release is! Map<String, dynamic> ||
          release['draft'] != false ||
          release['prerelease'] != debug) {
        continue;
      }
      final tag = release['tag_name'];
      if (tag is! String || !seen.add(tag)) continue;
      final match = tagPattern.firstMatch(tag);
      if (match == null) continue;
      final build = int.tryParse(match.group(2)!);
      if (build == null || build <= 0 ||
          (debug ? build < 100000 || build >= 2147483647 : build >= 1000)) {
        continue;
      }
      final files = release['assets'];
      if (files is! List) continue;
      final artifacts = <UpdateArtifact>[];
      final assetAbis = <String>{};
      final allowedBase = 'https://github.com/mibesamiti-png/'
          'chappy-player-updates/releases/download/$tag/';
      for (final asset in files) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'];
        final digest = asset['digest'];
        final size = asset['size'];
        final url = asset['browser_download_url'];
        if (name is! String || digest is! String ||
            size is! int || url is! String) {
          continue;
        }
        final abiMatch = debug ? null : RegExp(
            r'^ChappyPlayer-(arm64-v8a|armeabi-v7a|x86_64)\.apk$')
            .firstMatch(name);
        if ((!debug && abiMatch == null) ||
            (debug && name != 'ChappyPlayerDebug.apk') ||
            !digest.startsWith('sha256:') ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
            size < 1024 || size > UpdateService.maxApkBytes ||
            url != '$allowedBase$name') {
          continue;
        }
        final abi = debug ? 'universal' : abiMatch!.group(1)!;
        if (!assetAbis.add(abi)) {
          continue;
        }
        artifacts.add(UpdateArtifact(
          abi, Uri.parse(url), digest.substring(7).toLowerCase(), size,
          androidVersionCode: debug ? build : build + offsets[abi]!,
        ));
      }
      if (debug ? assetAbis.length != 1 || !assetAbis.contains('universal')
                : assetAbis.length != 3) {
        continue;
      }
      final notes = release['body'];
      releases.add(UpdateRelease(
        packageId: debug ? chappyDebugPackageId : chappyProductionPackageId,
        version: match.group(1)!,
        buildNumber: debug ? build : 4000 + build,
        releaseNotes: notes is String ? notes.substring(
            0, notes.length > 3000 ? 3000 : notes.length) : '',
        artifacts: List.unmodifiable(artifacts),
      ));
    }
    releases.sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
    return List.unmodifiable(releases);
  }

  Future<List<UpdateRelease>> fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(chappyApkHistoryApi))
          .timeout(const Duration(seconds: 12));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'ChappyPlayer/1.0');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await req.close().timeout(
          const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('リリース一覧を取得できません (HTTP ${response.statusCode})');
      }
      const maxJson = 256 * 1024;
      var total = 0;
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 20))) {
        total += part.length;
        if (total > maxJson) {
          throw const FormatException('リリース一覧が大きすぎます');
        }
        bytes.addAll(part);
      }
      return parse(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}
