import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A public, token-free catalog distinct from the private player source and
/// the APK-only distribution repository. The repository must be created once
/// by its owner before the catalog can show packages.
const chappyAppsCatalogUrl =
    'https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/main/catalog.json';

const _maxChappyBytes = 12 * 1024 * 1024;
const _maxCatalogBytes = 64 * 1024;

int compareChappyVersions(String a, String b) {
  final version = RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$');
  if (!version.hasMatch(a) || !version.hasMatch(b)) {
    throw const FormatException('バージョン番号が不正です');
  }
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// Forbid arbitrary executable downloads. Only the owner's public mini-app
/// repository may host .chappy bytes, with channel-specific directories.
bool isTrustedChappyDownload(Uri uri, String channel,
    {bool allowLoopbackForTests = false}) {
  if (uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery) return false;
  if (allowLoopbackForTests &&
      uri.scheme == 'http' &&
      (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
    return uri.path.endsWith('.chappy');
  }
  if (uri.scheme != 'https' || uri.host != 'raw.githubusercontent.com' ||
      uri.port != 443) {
    return false;
  }
  final parts = uri.pathSegments;
  if (parts.length < 5 ||
      parts[0] != 'mibesamiti-png' ||
      parts[1] != 'chappy-apps' ||
      parts[2] != 'main' ||
      parts[3] != channel ||
      (channel != 'stable' && channel != 'debug') ||
      !parts.last.toLowerCase().endsWith('.chappy')) {
    return false;
  }
  return parts.every((part) => part.isNotEmpty && part != '.' &&
      part != '..' && !part.contains('/') && !part.contains('\\'));
}

class ChappyCatalogEntry {
  final String id;
  final String name;
  final String description;
  final String version;
  final String channel;
  final Uri url;
  final String sha256Hex;
  final int sizeBytes;

  const ChappyCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.channel,
    required this.url,
    required this.sha256Hex,
    required this.sizeBytes,
  });

  factory ChappyCatalogEntry.parse(Object? data,
      {bool allowLoopbackForTests = false}) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('アプリ情報が不正です');
    }
    final id = data['id'];
    final name = data['name'];
    final description = data['description'];
    final version = data['version'];
    final channel = data['channel'];
    final download = data['url'];
    final digest = data['sha256'];
    final size = data['sizeBytes'];
    if (id is! String ||
        !RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$')
            .hasMatch(id) || id.length > 100 ||
        name is! String || name.trim().isEmpty || name.length > 60 ||
        description is! String || description.length > 500 ||
        version is! String ||
        channel is! String || !{'stable', 'debug'}.contains(channel) ||
        download is! String || download.length > 2048 ||
        digest is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest) ||
        size is! int || size < 100 || size > _maxChappyBytes) {
      throw const FormatException('カタログの項目が不正です');
    }
    compareChappyVersions(version, version);
    final uri = Uri.tryParse(download);
    if (uri == null || !isTrustedChappyDownload(uri, channel,
        allowLoopbackForTests: allowLoopbackForTests)) {
      throw const FormatException('公開元が許可されていない.chappyファイルです');
    }
    return ChappyCatalogEntry(
      id: id, name: name, description: description, version: version,
      channel: channel, url: uri, sha256Hex: digest.toLowerCase(),
      sizeBytes: size,
    );
  }
}

class ChappyCatalog {
  final List<ChappyCatalogEntry> entries;
  const ChappyCatalog(this.entries);

  factory ChappyCatalog.parse(String content,
      {bool allowLoopbackForTests = false}) {
    final raw = jsonDecode(content);
    if (raw is! Map<String, dynamic> || raw['schemaVersion'] != 1 ||
        raw['entries'] is! List) {
      throw const FormatException('未対応のChappy Appsカタログです');
    }
    final entries = raw['entries'] as List;
    if (entries.length > 100) {
      throw const FormatException('カタログに登録できるアプリは100件までです');
    }
    final result = entries.map((data) => ChappyCatalogEntry.parse(data,
        allowLoopbackForTests: allowLoopbackForTests)).toList();
    final keys = <String>{};
    for (final item in result) {
      if (!keys.add('${item.channel}/${item.id}')) {
        throw const FormatException('同じアプリID・チャンネルが重複しています');
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return ChappyCatalog(List.unmodifiable(result));
  }

  List<ChappyCatalogEntry> forChannel(String channel) =>
      entries.where((item) => item.channel == channel).toList();
}

class ChappyCatalogService {
  final bool allowInsecureLoopbackForTests;
  const ChappyCatalogService({this.allowInsecureLoopbackForTests = false});

  bool _validCatalogUrl(Uri uri) {
    if (allowInsecureLoopbackForTests &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost')) return true;
    return uri.toString() == chappyAppsCatalogUrl;
  }

  Future<Uint8List> _read(Uri url, int limit,
      {void Function(int, int)? onProgress,
       int? expectedLength}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url)
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close()
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHubの取得に失敗しました (HTTP ${response.statusCode})');
      }
      if (response.contentLength > limit ||
          (expectedLength != null && response.contentLength >= 0 &&
           response.contentLength != expectedLength)) {
        throw const FormatException('配信ファイルのサイズが一致しません');
      }
      final collected = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        count += chunk.length;
        if (count > limit ||
            (expectedLength != null && count > expectedLength)) {
          throw const FormatException('ダウンロードサイズが上限を超えました');
        }
        collected.add(chunk);
        onProgress?.call(count, expectedLength ?? limit);
      }
      if (expectedLength != null && count != expectedLength) {
        throw const FormatException('ダウンロードが途中で終了しました');
      }
      return collected.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<ChappyCatalog> fetch({Uri? source}) async {
    final url = source ?? Uri.parse(chappyAppsCatalogUrl);
    if (!_validCatalogUrl(url)) {
      throw const FormatException('Chappy Apps公式カタログ以外は読み込めません');
    }
    final bytes = await _read(url, _maxCatalogBytes);
    return ChappyCatalog.parse(utf8.decode(bytes),
        allowLoopbackForTests: allowInsecureLoopbackForTests);
  }

  /// Download and verify package bytes, but never install or execute here.
  Future<Uint8List> download(ChappyCatalogEntry entry,
      {void Function(int, int)? onProgress}) async {
    if (!isTrustedChappyDownload(entry.url, entry.channel,
        allowLoopbackForTests: allowInsecureLoopbackForTests)) {
      throw const FormatException('許可されていないダウンロードURLです');
    }
    final data = await _read(entry.url, _maxChappyBytes,
        onProgress: onProgress, expectedLength: entry.sizeBytes);
    if (sha256.convert(data).toString() != entry.sha256Hex) {
      throw const FormatException('ダウンロードした.chappyのSHA-256が一致しません');
    }
    return data;
  }
}
