import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/apk_upgrade_checker.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/update_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class PlayerUpdatePage extends StatefulWidget {
  final LogStore logs;
  const PlayerUpdatePage({super.key, required this.logs});

  @override
  State<PlayerUpdatePage> createState() => _PlayerUpdatePageState();
}

class _PlayerUpdatePageState extends State<PlayerUpdatePage> {
  final UpdateService _updates = UpdateService();
  final ApkUpgradeChecker _apkChecker = const ApkUpgradeChecker();
  PackageInfo? _installed;
  UpdateRelease? _release;
  UpdateArtifact? _artifact;
  String? _error;
  String _status = 'まだ確認していません';
  bool _busy = false;
  int _received = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInstalled());
  }

  Future<void> _loadInstalled() async {
    try {
      final installed = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _installed = installed);
    } catch (error) {
      await widget.logs.add('player', 'warning', 'update',
          'Could not query app build number: $error');
      if (mounted) setState(() => _error = '端末のアプリ情報を取得できませんでした');
    }
  }

  int? get _installedBuild => int.tryParse(_installed?.buildNumber ?? '');

  Future<void> _check() async {
    if (_busy || chappyUpdateFeedUrl.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'HTTPSで更新情報を確認しています…';
      _release = null;
      _artifact = null;
    });
    try {
      final url = Uri.parse(chappyUpdateFeedUrl);
      final release = await _updates.fetch(url);
      final installed = _installedBuild;
      if (installed == null) {
        throw StateError('インストール済みビルド番号が不明です');
      }
      if (release.packageId != _installed?.packageName) {
        throw const FormatException('更新先アプリのIDが一致しません');
      }
      final artifact = release.forAbi(currentAndroidAbi());
      if (mounted) {
        setState(() {
          _release = release;
          _artifact = artifact;
          _status = !release.newerThan(installed)
              ? '現在のバージョンが最新です'
              : artifact == null
                  ? '更新がありますが、この端末向けAPKがありません'
                  : '新しいバージョンが見つかりました';
        });
      }
      await widget.logs.add('player', 'info', 'update',
          'Update check succeeded; remote build ${release.buildNumber}');
    } catch (error) {
      await widget.logs.add('player', 'warning', 'update',
          'Update check failed: $error');
      if (mounted) {
        setState(() {
          _error = '$error';
          _status = '更新を確認できませんでした';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy || _artifact == null) return;
    final artifact = _artifact!;
    setState(() {
      _busy = true;
      _error = null;
      _received = 0;
      _total = artifact.sizeBytes;
      _status = 'APKをダウンロードして検証しています…';
    });
    File? downloaded;
    try {
      final cache = await getTemporaryDirectory();
      downloaded = await _updates.download(
        artifact,
        Directory('${cache.path}/chappy_updates'),
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      // Verify the *actual APK* identity and Android signing certificate
      // BEFORE exporting the file or asking the user to install it.
      // SHA-256 verifies download integrity, not compatibility with the
      // already-installed package.
      final compatibility = await _apkChecker.inspect(downloaded);
      await widget.logs.add('player',
          compatibility.compatible ? 'info' : 'warning',
          'apk-preflight',
          'APK preflight: ${compatibility.code} '
          '(installed=${compatibility.installedBuild}, '
          'candidate=${compatibility.candidateBuild})');
      if (!compatibility.compatible) {
        if (mounted) {
          setState(() {
            _error = compatibility.userMessage;
            _status = '上書き互換性チェックで更新を中止しました';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() => _status = 'APKの署名・バージョン確認成功。保存先を選んでください');
      // SAF saveFile is used rather than exposing private cache file:// URIs.
      final data = Uint8List.fromList(await downloaded.readAsBytes());
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Chappy Player更新APKの保存先',
        fileName: 'ChappyPlayer-${artifact.abi}.apk',
        type: FileType.any,
        bytes: data,
      );
      if (saved == null) {
        if (mounted) setState(() => _status = '保存をキャンセルしました');
        return;
      }
      await widget.logs.add('player', 'info', 'update',
          'Verified update APK exported to Android document picker');
      if (mounted) {
        setState(() => _status = 'APKを保存しました。ファイル管理アプリから開いて更新してください');
      }
    } catch (error) {
      await widget.logs.add('player', 'error', 'update', 'APK download failed: $error');
      if (mounted) {
        setState(() {
          _error = '$error';
          _status = 'APKの取得・保存に失敗しました';
        });
      }
    } finally {
      if (downloaded != null && await downloaded.exists()) {
        await downloaded.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installedBuild = _installedBuild;
    final release = _release;
    final artifact = _artifact;
    final canDownload = !_busy && release != null &&
        artifact != null && installedBuild != null &&
        release.newerThan(installedBuild);
    return Scaffold(
      appBar: AppBar(title: const Text('プレイヤー本体の更新')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Text('Chappy Player 更新センター',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('現在のバージョン：${_installed?.version ?? '確認中'} '
              '(ビルド ${_installed?.buildNumber ?? '—'})'),
          const SizedBox(height: 4),
          Text('端末CPU：${currentAndroidAbi() ?? '未対応のCPU'}'),
          const SizedBox(height: 18),
          if (chappyUpdateFeedUrl.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('更新配信先はまだ未設定です。'
                  'GitHubのソースコードは非公開のまま、'
                  '署名済みAPKと更新情報を安全に配信する設定が必要です。'
                  '現時点では自動更新は利用できません。'),
            )),
          FilledButton.icon(
            onPressed: _busy || chappyUpdateFeedUrl.isEmpty ? null : _check,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('最新版を確認'),
          ),
          const SizedBox(height: 12),
          Text(_status),
          if (_error != null) ...[
            const SizedBox(height: 10),
            SelectableText('詳細：$_error',
                style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if (_busy && _total > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _received / _total),
            Text('${(_received / 1024 / 1024).toStringAsFixed(1)}'
                ' / ${(_total / 1024 / 1024).toStringAsFixed(1)} MiB'),
          ],
          if (release != null) ...[
            const SizedBox(height: 20),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('配布版：v${release.version}（ビルド ${release.buildNumber}）',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(release.releaseNotes),
                const SizedBox(height: 10),
                Text(artifact == null
                    ? 'このCPUに対応するAPKはありません'
                    : '対応APK：${artifact.abi} / '
                        '${(artifact.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MiB'),
              ]),
            )),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: canDownload ? _download : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('検証してAPKを保存'),
          ),
          const SizedBox(height: 16),
          const Text(
            '注意：保存したAPKのインストールはAndroid側の確認操作が必要です。'
            '現在のデバッグAPKと新しい署名付きAPKでは上書きできない場合があります。'
            'アンインストールすると保存データが消えるため、'
            '更新前に必ずバックアップを取ってください。'
            'ダウンロードしたAPKの署名証明書・アプリID・ビルド番号を確認し、'
            '不一致の場合は保存前に更新を中止します。'
            'この画面は自動でAPKをインストールしません。',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ]),
      ),
    );
  }
}
