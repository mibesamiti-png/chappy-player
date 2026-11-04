import 'dart:io';

import 'package:flutter/services.dart';

/// Android's installer makes the final decision; this is a conservative,
/// fail-closed preview so users are not asked to uninstall and lose their data.
class ApkCompatibilityResult {
  final bool compatible;
  final String code;
  final int installedBuild;
  final int candidateBuild;

  const ApkCompatibilityResult({
    required this.compatible,
    required this.code,
    required this.installedBuild,
    required this.candidateBuild,
  });

  factory ApkCompatibilityResult.fromNative(Map<dynamic, dynamic> data) {
    final compatible = data['compatible'];
    final code = data['code'];
    final oldBuild = data['installedBuild'];
    final newBuild = data['candidateBuild'];
    if (compatible is! bool || code is! String ||
        oldBuild is! num || newBuild is! num) {
      throw const FormatException('Androidから不正なAPK互換性情報が返されました');
    }
    return ApkCompatibilityResult(
      compatible: compatible,
      code: code,
      installedBuild: oldBuild.toInt(),
      candidateBuild: newBuild.toInt(),
    );
  }

  String get userMessage => switch (code) {
    'COMPATIBLE' =>
      'アプリID・署名証明書・バージョン番号の事前確認に成功しました。'
      '最終的な上書き可否はAndroidが判断します。',
    'SIGNATURE_MISMATCH' =>
      '現在のChappy Playerと新しいAPKの署名鍵が違います。'
      'このまま上書きはできません。削除すると保存データが消えるため、'
      '今はアンインストールせずバックアップと固定署名設定を確認してください。',
    'VERSION_NOT_NEWER' =>
      '新しいAPKのバージョン番号が現在のアプリより大きくありません。'
      '上書き用の新しいビルドが必要です。',
    'PACKAGE_ID_MISMATCH' =>
      '新しいAPKのアプリIDがChappy Playerと一致しません。',
    'SIGNATURE_UNREADABLE' =>
      'APKの署名を確認できないため、安全のため更新を中止しました。',
    'INVALID_PATH' || 'APK_UNREADABLE' =>
      'AndroidがAPKファイルを読み取れませんでした。',
    _ => 'APKの互換性を確認できませんでした ($code)。',
  };
}

class ApkUpgradeChecker {
  static const channelName = 'dev.chappy.player/update';
  final MethodChannel _channel;
  const ApkUpgradeChecker({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  Future<ApkCompatibilityResult> inspect(File file) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APKの上書き互換性確認はAndroid専用です');
    }
    try {
      final values = await _channel.invokeMapMethod<String, dynamic>(
        'checkApkCompatibility', {'path': file.absolute.path},
      );
      if (values == null) {
        throw const FormatException('Androidから確認結果がありません');
      }
      return ApkCompatibilityResult.fromNative(values);
    } on MissingPluginException {
      throw const FormatException(
        'このプレイヤーはAPK署名の事前確認に未対応です。'
        '新しい署名付きAPKで機能を有効にしてください',
      );
    }
  }
}
