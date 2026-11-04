import 'dart:async';
import 'dart:io';

import 'package:chappy_player/core/apk_release_history_service.dart';
import 'package:chappy_player/core/apk_upgrade_checker.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/update_service.dart';
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
  final ApkReleaseHistoryService _releaseHistory =
      const ApkReleaseHistoryService();
  List<UpdateRelease> _history = const [];
  String? _historyError;
  final ApkUpgradeChecker _apkChecker = const ApkUpgradeChecker();
  PackageInfo? _installed;
  UpdateRelease? _release;
  UpdateArtifact? _artifact;
  String? _error;
  String _status = 'まだ確認していません';
  bool _busy = false;
  int _received = 0;
  int _total = 0;
  File? _pendingInstallApk;

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
      _history = const [];
      _historyError = null;
      _pendingInstallApk = null;
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
          _status = !release.newerThan(installed, abi: currentAndroidAbi())
              ? '現在のバージョンが最新です'
              : artifact == null
                  ? '更新がありますが、この端末向けAPKがありません'
                  : '新しいバージョンが見つかりました';
        });
      }
      try {
        final history = await _releaseHistory.fetch();
        if (mounted) setState(() => _history = history);
      } catch (error) {
        // Latest signed feed still works when GitHub API is rate-limited.
        if (mounted) setState(() => _historyError = '$error');
        await widget.logs.add('player', 'warning', 'release-history',
            'Optional release list could not be read: $error');
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

  void _selectHistoryRelease(UpdateRelease choice) {
    final installed = _installedBuild;
    final cpu = currentAndroidAbi();
    final artifact = choice.forAbi(cpu);
    if (_busy || _pendingInstallApk != null || installed == null ||
        artifact == null || !choice.newerThan(installed, abi: cpu)) {
      return;
    }
    setState(() {
      _release = choice;
      _artifact = artifact;
      _status = 'v${choice.version}（ビルド ${artifact.androidVersionCode ?? choice.buildNumber}）'
          ' を選択しました。ダウンロードして更新できます。';
    });
  }

  /// Perform strict local Android checks again before every installer handoff.
  Future<void> _openAndroidInstaller(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('保存済みの更新APKが見つかりません');
    }
    final check = await _apkChecker.inspect(file);
    await widget.logs.add('player',
        check.compatible ? 'info' : 'warning',
        'apk-preflight',
        'APK: ${check.code} (${check.installedBuild} -> ${check.candidateBuild})');
    if (!check.compatible) {
      _pendingInstallApk = null;
      if (mounted) {
        setState(() {
          _error = check.userMessage;
          _status = '安全のためインストールを中止しました';
        });
      }
      return;
    }
    final handoff = await _apkChecker.launchInstaller(file);
    await widget.logs.add('player', 'info', 'apk-installer',
        'Android installer handoff: ${handoff.status} ${handoff.code ?? ''}');
    if (!mounted) return;
    if (handoff.installerOpened) {
      _pendingInstallApk = null;
      setState(() {
        _status = 'Androidのインストール確認画面を開きました。'
            '「更新」または「インストール」を選んでください。'
            '確認画面を開いた時点では、更新完了とは判定しません。';
      });
    } else if (handoff.needsPermission) {
      _pendingInstallApk = file;
      setState(() {
        _status = 'Androidの「この提供元を許可」画面を開きました。'
            '許可したらChappy Playerへ戻って「インストールを再開」を押してください。'
            'APKを再ダウンロードする必要はありません。';
      });
    } else {
      _pendingInstallApk = null;
      setState(() {
        _error = 'AndroidがAPKの起動を拒否しました'
            '（${handoff.code ?? '不明'}）。';
        _status = 'インストールは開始されていません';
      });
    }
  }

  Future<void> _resumeInstall() async {
    final file = _pendingInstallApk;
    if (_busy || file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _openAndroidInstaller(file);
    } catch (error) {
      await widget.logs.add('player', 'error', 'apk-installer', '$error');
      if (mounted) {
        setState(() {
          _error = '$error';
          _status = 'Androidのインストール画面を開けませんでした';
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
      _pendingInstallApk = null;
      _received = 0;
      _total = artifact.sizeBytes;
      _status = 'APKをダウンロードして検証しています…';
    });
    File? downloaded;
    var keepForInstaller = false;
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
      // The downloader already compared the file's SHA-256 and exact length.
      // Keep it in private cache so FileProvider can stream it to Android.
      if (!mounted) return;
      setState(() => _status = 'APK検証成功。インストール確認へ進みます…');
      await _openAndroidInstaller(downloaded);
      keepForInstaller = _pendingInstallApk != null ||
          _status.contains('インストール確認画面を開きました');
    } catch (error) {
      await widget.logs.add('player', 'error', 'update', 'APK update failed: $error');
      if (mounted) {
        setState(() {
          _error = '$error';
          _status = 'APKの取得・検証・インストール準備に失敗しました';
        });
      }
    } finally {
      if (!keepForInstaller && downloaded != null && await downloaded.exists()) {
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
    final canDownload = !_busy && _pendingInstallApk == null && release != null &&
        artifact != null && installedBuild != null &&
        release.newerThan(installedBuild, abi: currentAndroidAbi());
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
                Text('配布版：v${release.version}（APKビルド ${artifact?.androidVersionCode ?? release.buildNumber}）',
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
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('公開済みバージョン一覧',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Androidは古いAPKを上書きできません。'
                'インストール済みより新しい版だけ選択可能です。',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
            ..._history.map((item) {
              final cpu = currentAndroidAbi();
              final choice = item.forAbi(cpu);
              final available = installedBuild != null && choice != null &&
                  item.newerThan(installedBuild, abi: cpu);
              final selected = release?.version == item.version &&
                  release?.buildNumber == item.buildNumber;
              final detail = choice == null ? '非対応CPU' :
                  '${(choice.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MiB';
              return Card(
                child: ListTile(
                  title: Text('v${item.version}'),
                  subtitle: Text(
                      'Build ${choice?.androidVersionCode ?? '—'} · $detail'),
                  trailing: OutlinedButton(
                    onPressed: _busy || _pendingInstallApk != null ||
                            !available
                        ? null : () => _selectHistoryRelease(item),
                    child: Text(selected ? '選択中' :
                        available ? '選ぶ' : '更新不可'),
                  ),
                ),
              );
            }),
          ],
          if (_historyError != null) ...[
            const SizedBox(height: 8),
            Text('履歴一覧を取得できませんでした：$_historyError',
                style: const TextStyle(
                    color: Colors.orangeAccent, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: canDownload ? _download : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('ダウンロードして更新'),
          ),
          if (_pendingInstallApk != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _resumeInstall,
              icon: const Icon(Icons.system_update_alt_outlined),
              label: const Text('インストールを再開'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            '更新APKは署名・アプリID・ビルド番号を照合してから'
            'Android標準のインストール画面に渡します。'
            '実際の更新にはAndroid側での確認操作が必要です。'
            '現在のデバッグAPKと新しい署名付きAPKでは上書きできない場合があります。'
            'アンインストールすると保存データが消えるため、'
            '更新前に必ずバックアップを取ってください。'
            'ダウンロードしたAPKの署名証明書・アプリID・ビルド番号を確認し、'
            '不一致の場合は保存前に更新を中止します。'
            '無断でアンインストールしたり、無承認で更新を完了したりはしません。',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ]),
      ),
    );
  }
}
