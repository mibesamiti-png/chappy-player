import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A public HTTPS update feed. A private GitHub repo cannot be fetched by an
/// app without a token, so an official feed must be hosted separately.
/// Never put a GitHub PAT, signing secret, or private release URL in an APK.
const chappyUpdateFeedUrl = String.fromEnvironment('CHAPPY_UPDATE_FEED_URL');

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

  const UpdateArtifact(this.abi, this.url, this.sha256Hex, this.sizeBytes);

  static UpdateArtifact parse(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('APK情報の形式が不正です');
    }
    final abi = raw['abi'];
    final source = raw['url'];
    final digest = raw['sha256'];
    final size = raw['sizeBytes'];
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
    return UpdateArtifact(abi, url, digest.toLowerCase(), size);
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

  static UpdateRelease parse(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! Map<String, dynamic> ||
        raw['schemaVersion'] != 1 ||
        raw['packageId'] != 'dev.chappy.chappy_player') {
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

  bool newerThan(int installedBuild) => buildNumber > installedBuild;

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

  Future<UpdateRelease> fetch(Uri feedUrl) async {
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
      return UpdateRelease.parse(utf8.decode(bytes));
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
      final request = await client.getUrl(artifact.url)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final response = await request.close()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APKの取得に失敗 (HTTP ${response.statusCode})');
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
      return part.rename(finished.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
