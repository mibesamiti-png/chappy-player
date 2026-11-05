import 'dart:convert';

/// Explicit, install-time capabilities supported by this release.
const supportedChappyPermissions = <String>{'camera', 'microphone'};

String chappyPermissionsLabel(List<String> permissions) {
  if (permissions.isEmpty) return '追加権限なし';
  return permissions.map((permission) {
    switch (permission) {
      case 'camera':
        return 'カメラ';
      case 'microphone':
        return 'マイク';
      default:
        return '未対応の権限';
    }
  }).join('・');
}

class ChappyPackage {
  final String id;
  final String name;
  final String version;
  final String entry;
  final List<String> permissions;

  const ChappyPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.permissions,
  });

  static final RegExp _idPattern = RegExp(
    r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$',
  );
  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  static ChappyPackage parse(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('manifest.json はJSONオブジェクトが必要です');
    }
    if (decoded['formatVersion'] != 1) {
      throw const FormatException('未対応のformatVersionです（対応: 1）');
    }
    final id = decoded['id'];
    final name = decoded['name'];
    final version = decoded['version'];
    final entry = decoded['entry'];
    final permissions = decoded['permissions'];
    if (id is! String || !_idPattern.hasMatch(id) || id.length > 100) {
      throw const FormatException('不正なアプリIDです');
    }
    if (name is! String || name.trim().isEmpty || name.length > 60) {
      throw const FormatException('アプリ名は1〜60文字で指定してください');
    }
    if (version is! String || !_versionPattern.hasMatch(version)) {
      throw const FormatException('versionは例 0.1.0 の形式にしてください');
    }
    if (entry != 'index.html') {
      throw const FormatException('v0.1のentryはindex.htmlのみ対応です');
    }
    if (permissions is! List ||
        permissions.any((item) => item is! String ||
            !supportedChappyPermissions.contains(item)) ||
        permissions.toSet().length != permissions.length) {
      throw const FormatException('permissionsはcamera/microphoneのみ、重複なしで指定してください');
    }
    if (decoded['minPlayerVersion'] != null &&
        decoded['minPlayerVersion'] != '0.1.0') {
      throw const FormatException('このプレイヤーに対応していないminPlayerVersionです');
    }
    return ChappyPackage(
      id: id,
      name: name,
      version: version,
      entry: entry,
      permissions: List<String>.unmodifiable(permissions.cast<String>()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'entry': entry,
    'permissions': permissions,
  };

  factory ChappyPackage.fromJson(Map<String, dynamic> json) => ChappyPackage(
    id: json['id'] as String,
    name: json['name'] as String,
    version: json['version'] as String,
    entry: json['entry'] as String,
    permissions: List<String>.from(json['permissions'] as List),
  );
}

bool isSafeArchivePath(String fileName) {
  if (fileName.isEmpty || fileName.length > 240 || fileName.contains('\\')) {
    return false;
  }
  if (fileName.startsWith('/') || fileName.contains(':') || fileName.contains('\u0000')) {
    return false;
  }
  final segments = fileName.split('/');
  if (segments.asMap().entries.any((part) =>
      part.value == '..' ||
      part.value == '.' ||
      (part.value.isEmpty && part.key != segments.length - 1) ||
      part.value.contains(RegExp(r'[\x00-\x1f]')))) {
    return false;
  }
  if (segments.where((segment) => segment.isNotEmpty).isEmpty) return false;
  return true;
}
