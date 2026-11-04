import 'dart:async';
import 'dart:typed_data';

import 'package:chappy_player/core/chappy_catalog_service.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:flutter/material.dart';

class ChappyCatalogPage extends StatefulWidget {
  final PackageRepository repository;
  final LogStore logs;
  final VoidCallback onLibraryChanged;

  const ChappyCatalogPage({
    super.key,
    required this.repository,
    required this.logs,
    required this.onLibraryChanged,
  });

  @override
  State<ChappyCatalogPage> createState() => _ChappyCatalogPageState();
}

class _ChappyCatalogPageState extends State<ChappyCatalogPage> {
  final ChappyCatalogService _service = const ChappyCatalogService();
  ChappyCatalog? _catalog;
  String? _error;
  String _channel = 'stable';
  bool _busy = false;
  String? _downloadingId;
  int _downloaded = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final catalog = await _service.fetch();
      if (mounted) {
        setState(() => _catalog = catalog);
      }
      await widget.logs.add('player', 'info', 'catalog',
          'Chappy catalog fetched: ${catalog.entries.length} entries');
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
      await widget.logs.add('player', 'warning', 'catalog',
          'Could not fetch public catalog: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ChappyPackage? _installed(String id) {
    for (final app in widget.repository.apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  Future<bool> _confirmInstall(ChappyCatalogEntry item, ChappyPackage app,
      ChappyPackage? installed) async {
    if (!mounted) return false;
    final update = installed != null;
    final label = update ? '既存アプリの本体を更新' : '新しいアプリを追加';
    return await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: Text(
            'アプリ：${app.name}\n'
            'ID：${app.id}\n'
            'バージョン：${installed?.version ?? '未追加'} → ${app.version}\n'
            '配信チャンネル：${item.channel == 'debug' ? 'Debug' : 'Stable'}\n'
            '必要な追加権限：なし\n\n'
            '${item.channel == 'debug' ? 'これは開発・検証用の公開ファイルです。\n\n' : ''}'
            '提供元のコードを実行するため、信頼できる自作アプリだけを追加してください。'
            '${update ? ' 保存データは保持されます。' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(update ? '更新する' : '追加する'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _install(ChappyCatalogEntry item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _downloadingId = item.id;
      _downloaded = 0;
      _total = item.sizeBytes;
      _error = null;
    });
    try {
      final Uint8List bytes = await _service.download(item,
          onProgress: (received, total) {
        if (mounted) {
          setState(() {
            _downloaded = received;
            _total = total;
          });
        }
      });
      // Reuse the same ZIP validation as local imports before touching storage.
      final app = widget.repository.inspect(bytes);
      if (app.id != item.id || app.version != item.version) {
        throw const FormatException(
            'GitHubの登録情報と.chappy内部のID・バージョンが一致しません');
      }
      final installed = _installed(app.id);
      if (installed != null &&
          compareChappyVersions(item.version, installed.version) < 0) {
        throw const FormatException('現在より古いミニアプリへの更新はできません');
      }
      if (!await _confirmInstall(item, app, installed)) return;
      if (!mounted) return;
      await widget.repository.install(bytes);
      await widget.logs.add(app.id, 'info', 'catalog-install',
          'Installed public ${item.channel} package v${app.version}');
      widget.onLibraryChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${app.name} v${app.version} を追加・更新しました')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
      await widget.logs.add('player', 'error', 'catalog-install', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _downloadingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _catalog?.forChannel(_channel) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chappy Apps'),
        actions: [
          IconButton(
            tooltip: '公開カタログを更新',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('GitHub 公開ミニアプリライブラリ',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '公開リポジトリの一覧を表示します。ダウンロードはサイズとSHA-256、'
              'ZIP構造を検証し、確認後にのみ登録します。',
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'stable', label: Text('Stable 安定版'),
                    icon: Icon(Icons.verified_outlined)),
                ButtonSegment(value: 'debug', label: Text('Debug 開発版'),
                    icon: Icon(Icons.science_outlined)),
              ],
              selected: {_channel},
              onSelectionChanged: _busy ? null : (selection) {
                setState(() => _channel = selection.first);
              },
            ),
            if (_channel == 'debug') ...[
              const SizedBox(height: 8),
              const Text('Debugは動作検証用です。正式版より不安定な場合があります。',
                  style: TextStyle(color: Colors.orangeAccent)),
            ],
            if (_busy && _downloadingId == null) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              SelectableText('取得・登録エラー：$_error',
                  style: const TextStyle(color: Colors.orangeAccent)),
              const SizedBox(height: 8),
              const Text(
                '公開ライブラリがまだ作成されていない場合は、'
                'GitHubの chappy-apps リポジトリ公開後に再読込してください。',
              ),
            ],
            if (_catalog != null && entries.isEmpty) ...[
              const SizedBox(height: 24),
              const Center(child: Text('このチャンネルにはまだアプリがありません')),
            ],
            const SizedBox(height: 16),
            ...entries.map((item) {
              final installed = _installed(item.id);
              final relation = installed == null ? 1
                  : compareChappyVersions(item.version, installed.version);
              final action = installed == null ? '追加' :
                  relation > 0 ? '更新' :
                  relation == 0 ? '再インストール' : '旧版のため不可';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('${item.id} · v${item.version}'),
                      if (installed != null)
                        Text('インストール済み：v${installed.version}'),
                      const SizedBox(height: 8),
                      Text(item.description),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: Text('${(item.sizeBytes / 1024).toStringAsFixed(0)} KiB',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        FilledButton.tonal(
                          onPressed: _busy || relation < 0
                              ? null : () => _install(item),
                          child: Text(action),
                        ),
                      ]),
                      if (_busy && _downloadingId == item.id && _total > 0)
                        LinearProgressIndicator(value: _downloaded / _total),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            const Text(
              'StableとDebugは同じアプリIDを共有する場合があります。'
              'Debugで更新すると既存アプリ本体が置き換わるため、'
              '大切なメモはバックアップしてください。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
