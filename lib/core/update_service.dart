import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A public HTTPS update feed. A private GitHub repo cannot be fetched by an
/// app without a token, so an official feed must be hosted separately.
/// Never put a GitHub PAT, signing secret, or private release URL in an APK.
const chappyUpdateFeedUrl = String.fromEnvironment('CHAPPY_UPDATE_FEED_URL');

/// Debug uses a distinct *public* feed and app ID. No auth token is embedded.
const chappyDebugUpdateFeedUrl =
    'https://raw.githubusercontent.com/mibesamiti-png/'
    'chappy-player-updates/main/debug-update.json';
const chappyProductionPackageId = 'dev.chappy.chappy_player';
const chappyDebugPackageId = 'dev.chappy.chappy_player.debug';

String? currentAndroidAbi() {
  final abi = Abi.current();
  if (abi == Abi.androidArm64) return 'arm64-v8a';
  if (abi == Abi.androidArm) return 'armeabi-v7a';
  if (abi == Abi.androidX64) return 'x86_64';
  return null;
}

class UpdateArtifact {
  final String abi;
  final Uri url;
  final String sha256Hex;
  final int sizeBytes;
  /// The exact Android versionCode inside this ABI-specific signed APK.
  final int? androidVersionCode;

  const UpdateArtifact(this.abi, this.url, this.sha256Hex, this.sizeBytes,
      {this.androidVersionCode});

  static UpdateArtifact parse(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('APK情報の形式が不正です');
    }
    final abi = raw['abi'];
    final source = raw['url'];
    final digest = raw['sha256'];
    final size = raw['sizeBytes'];
    final nativeBuild = raw['androidVersionCode'];
    if (abi is! String ||
        !{'arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'}.contains(abi)) {
      throw const FormatException('未対応のAPK CPU形式です');
    }
    if (source is! String || source.length > 2048) {
      throw const FormatException('APKのURLが不正です');
    }
    final url = Uri.tryParse(source);
    if (url == null || !isSafeHttpsUrl(url)) {
      throw const FormatException('APKはHTTPSから取得する必要があります');
    }
    if (digest is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('SHA-256が不正です');
    }
    if (size is! int || size < 1024 || size > UpdateService.maxApkBytes) {
      throw const FormatException('APKのサイズが許容範囲外です');
    }
    if (nativeBuild != null && (nativeBuild is! int ||
        nativeBuild < 1 || nativeBuild > 2147483647)) {
      throw const FormatException('APKのAndroidビルド番号が不正です');
    }
    return UpdateArtifact(abi, url, digest.toLowerCase(), size,
        androidVersionCode: nativeBuild as int?);
  }
}

class UpdateRelease {
  final String packageId;
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final List<UpdateArtifact> artifacts;

  const UpdateRelease({
    required this.packageId,
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.artifacts,
  });

  static UpdateRelease parse(String jsonText, {
    String expectedPackageId = chappyProductionPackageId,
  }) {
    if (expectedPackageId != chappyProductionPackageId &&
        expectedPackageId != chappyDebugPackageId) {
      throw const FormatException('Unknown application update channel');
    }
    final raw = jsonDecode(jsonText);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != 1 ||
        raw['packageId'] != expectedPackageId) {
      throw const FormatException('未対応のChappy Player更新情報です');
    }
    final version = raw['version'];
    final build = raw['buildNumber'];
    final notes = raw['releaseNotes'];
    final entries = raw['artifacts'];
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const FormatException('更新バージョンが不正です');
    }
    if (build is! int || build < 1 || build > 2147483647) {
      throw const FormatException('更新ビルド番号が不正です');
    }
    if (notes is! String || notes.length > 3000 ||
        entries is! List || entries.isEmpty || entries.length > 4) {
      throw const FormatException('更新情報が不完全です');
    }
    final artifacts = entries.map(UpdateArtifact.parse).toList();
    final unique = artifacts.map((item) => item.abi).toSet();
    if (unique.length != artifacts.length) {
      throw const FormatException('CPU形式が重複しています');
    }
    return UpdateRelease(
      packageId: raw['packageId'] as String,
      version: version,
      buildNumber: build,
      releaseNotes: notes,
      artifacts: List.unmodifiable(artifacts),
    );
  }

  /// Prefer per-ABI actual versionCode; split-per-abi APKs add 1000/2000/4000.
  /// The top-level buildNumber is legacy-only fallback for older feeds.
  bool newerThan(int installedBuild, {String? abi}) {
    final candidate = forAbi(abi)?.androidVersionCode ?? buildNumber;
    return candidate > installedBuild;
  }

  UpdateArtifact? forAbi(String? deviceAbi) {
    for (final item in artifacts) {
      if (item.abi == deviceAbi) return item;
    }
    for (final item in artifacts) {
      if (item.abi == 'universal') return item;
    }
    return null;
  }
}

bool isSafeHttpsUrl(Uri url) =>
    url.scheme == 'https' &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty &&
    url.fragment.isEmpty &&
    (url.port == 443 || !url.hasPort);

/// GitHub Releases uses a temporary HTTPS CDN URL for binary assets.
/// Never permit a cross-origin redirect except the known GitHub asset CDNs.
bool isSafeUpdateRedirect(Uri initial, Uri next,
    {bool allowLoopbackTest = false}) {
  if (next.userInfo.isNotEmpty || next.fragment.isNotEmpty) return false;
  final sameOrigin = initial.scheme == next.scheme &&
      initial.host == next.host && initial.port == next.port;
  if (sameOrigin && (isSafeHttpsUrl(next) ||
      (allowLoopbackTest && initial.scheme == 'http' &&
       (initial.host == '127.0.0.1' || initial.host == 'localhost')))) {
    return true;
  }
  if (initial.scheme == 'https' && initial.host == 'github.com' &&
      isSafeHttpsUrl(next) &&
      (next.host == 'release-assets.githubusercontent.com' ||
       next.host == 'objects.githubusercontent.com')) {
    return true;
  }
  return false;
}

class UpdateService {
  static const maxFeedBytes = 64 * 1024;
  static const maxApkBytes = 180 * 1024 * 1024;

  /// Test-only loopback HTTP can be enabled by tests. Production defaults
  /// to HTTPS only, and redirects are always refused.
  final bool allowInsecureLoopbackForTests;
  UpdateService({this.allowInsecureLoopbackForTests = false});

  void _validateUrl(Uri url) {
    if (isSafeHttpsUrl(url)) return;
    if (allowInsecureLoopbackForTests &&
        url.scheme == 'http' &&
        (url.host == '127.0.0.1' || url.host == 'localhost') &&
        url.userInfo.isEmpty && url.fragment.isEmpty) {
      return;
    }
    throw const FormatException('更新はHTTPSの正規配布元からのみ取得できます');
  }

  Future<UpdateRelease> fetch(Uri feedUrl, {
    String expectedPackageId = chappyProductionPackageId,
  }) async {
    _validateUrl(feedUrl);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(feedUrl)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('更新情報を取得できません (HTTP ${response.statusCode})');
      }
      var total = 0;
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 12))) {
        total += part.length;
        if (total > maxFeedBytes) {
          throw const FormatException('更新情報が大きすぎます');
        }
        bytes.addAll(part);
      }
      return UpdateRelease.parse(utf8.decode(bytes),
          expectedPackageId: expectedPackageId);
    } finally {
      client.close(force: true);
    }
  }

  /// Download into a private cache, with strict bounds and SHA-256 verification.
  /// Does NOT install the APK. Android's installer and signing checks remain
  /// separate and mandatory before any automatic handoff.
  Future<File> download(
    UpdateArtifact artifact,
    Directory cacheRoot, {
    void Function(int bytesReceived, int bytesTotal)? onProgress,
  }) async {
    _validateUrl(artifact.url);
    await cacheRoot.create(recursive: true);
    final part = File(p.join(cacheRoot.path, 'chappy-update.part'));
    final finished = File(p.join(cacheRoot.path, 'chappy-update.apk'));
    if (await part.exists()) await part.delete();
    if (await finished.exists()) await finished.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      // GitHub Releases returns a temporary redirect to its asset CDN.
      // Permit only known HTTPS CDN destinations and limit the number of hops.
      var current = artifact.url;
      HttpClientResponse? response;
      for (var hop = 0; hop <= 3; hop++) {
        _validateUrl(current);
        final request = await client.getUrl(current)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        final candidate = await request.close()
            .timeout(const Duration(seconds: 15));
        if (candidate.statusCode == HttpStatus.ok) {
          response = candidate;
          break;
        }
        if (![301, 302, 303, 307, 308].contains(candidate.statusCode)) {
          throw HttpException(
              'APKの取得に失敗 (HTTP ${candidate.statusCode})');
        }
        final location = candidate.headers.value(HttpHeaders.locationHeader);
        await candidate.drain<void>();
        if (location == null || hop == 3) {
          throw const FormatException('APKのリダイレクト回数が多すぎます');
        }
        final next = current.resolve(location);
        if (!isSafeUpdateRedirect(current, next,
            allowLoopbackTest: allowInsecureLoopbackForTests)) {
          throw const FormatException('許可されていないAPKの転送先です');
        }
        current = next;
      }
      if (response == null) {
        throw const FormatException('APK配信先にアクセスできません');
      }
      if (response.contentLength > maxApkBytes ||
          (response.contentLength >= 0 &&
              response.contentLength != artifact.sizeBytes)) {
        throw const FormatException('配信されたAPKサイズが一致しません');
      }
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > maxApkBytes || received > artifact.sizeBytes) {
            throw const FormatException('APKのサイズ上限を超えました');
          }
          sink.add(chunk);
          onProgress?.call(received, artifact.sizeBytes);
        }
      } finally {
        await sink.close();
      }
      if (received != artifact.sizeBytes) {
        throw const FormatException('APKのダウンロードが途中で終了しました');
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != artifact.sha256Hex) {
        throw const FormatException('APKのSHA-256検証に失敗しました');
      }
      return await part.rename(finished.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
