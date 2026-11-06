import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:chappy_player/core/backup_export_service.dart';
import 'package:chappy_player/core/data_backup_service.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/screens/app_runner_page.dart';
import 'package:chappy_player/screens/chappy_catalog_page.dart';
import 'package:chappy_player/screens/logs_page.dart';
import 'package:chappy_player/screens/network_lab_page.dart';
import 'package:chappy_player/screens/player_update_page.dart';
import 'package:chappy_player/screens/self_check_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logs = LogStore();
  await logs.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(logs.add('player', 'error', 'flutter',
        '${details.exception}\n${details.stack ?? ''}'));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(logs.add('player', 'error', 'platform', '$error\n$stack'));
    return true;
  };
  runApp(ChappyApp(logs: logs));
}

class ChappyApp extends StatefulWidget {
  final LogStore logs;
  const ChappyApp({super.key, required this.logs});

  @override
  State<ChappyApp> createState() => _ChappyAppState();
}

class _ChappyAppState extends State<ChappyApp> {
  final PackageRepository repository = PackageRepository();
  late final Future<void> initialization = repository.init();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chappy Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F83FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF10151F),
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/logs') {
          return MaterialPageRoute<void>(
            builder: (_) => LogsPage(
              logs: widget.logs,
              appId: settings.arguments as String?,
            ),
          );
        }
        return null;
      },
      home: FutureBuilder<void>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Chappy Player')),
              body: Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: SelectableText('起動データの読み込みに失敗しました。\n${snapshot.error}'),
              )),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return HomePage(repository: repository, logs: widget.logs);
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final PackageRepository repository;
  final LogStore logs;
  const HomePage({super.key, required this.repository, required this.logs});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool busy = false;
  bool _externalReceiving = false;
  bool _externalQueued = false;
  static const MethodChannel _externalChannel =
      MethodChannel('dev.chappy.player/external_chappy');

  @override
  void initState() {
    super.initState();
    _externalChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingChappyAvailable') {
        _signalExternalImport();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signalExternalImport();
    });
  }

  @override
  void dispose() {
    _externalChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _signalExternalImport() {
    _externalQueued = true;
    unawaited(_consumeExternalChappy());
  }

  Future<void> _consumeExternalChappy() async {
    if (!mounted || busy || _externalReceiving) return;
    _externalReceiving = true;
    try {
      while (mounted && !busy) {
        _externalQueued = false;
        final result = await _externalChannel
            .invokeMapMethod<String, dynamic>('takePendingChappy');
        if (result == null) break;
        final path = result['path'];
        final name = result['fileName'];
        if (path is! String || name is! String ||
            !name.toLowerCase().endsWith('.chappy')) {
          throw const FormatException('Androidからの.chappy情報が不正です');
        }
        final file = File(path);
        try {
          final length = await file.length();
          if (length < 22 || length > 12 * 1024 * 1024) {
            throw const FormatException('外部.chappyのサイズが不正です');
          }
          await _importBytes(await file.readAsBytes());
        } finally {
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } catch (error) {
      await widget.logs.add('player', 'error', 'external-import', '$error');
      _notify('外部ファイルの読み込みに失敗: $error');
    } finally {
      _externalReceiving = false;
      if (_externalQueued && mounted && !busy) {
        unawaited(_consumeExternalChappy());
      }
    }
  }

  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  void _notify(String message) {
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('実行')),
        ],
      ),
    ) ?? false;
  }

  Future<void> _import() async {
    if (busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      if (!picked.name.toLowerCase().endsWith('.chappy')) {
        throw const FormatException('.chappyファイルを選択してください');
      }
      final bytes = picked.bytes ??
          (picked.path != null ? await FileBytes.read(picked.path!) : null);
      if (bytes == null) {
        throw const FormatException('選択したファイルを読み取れませんでした');
      }
      await _importBytes(Uint8List.fromList(bytes));
    } catch (error) {
      await widget.logs.add('player', 'error', 'import', error.toString());
      _notify('インポート失敗: $error');
    }
  }

  /// Shared installer: Files app, share sheet, and in-app picker all require
  /// the same ZIP preflight and an explicit confirmation before replacing.
  Future<void> _importBytes(Uint8List bytes) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (bytes.length > 12 * 1024 * 1024) {
        throw const FormatException('ファイルサイズが上限（12MiB）を超えています');
      }
      final incoming = widget.repository.inspect(bytes);
      final matches = widget.repository.apps.where((a) => a.id == incoming.id);
      final installed = matches.isEmpty ? null : matches.first;
      if (!mounted) return;
      final action = installed == null ? 'アプリを追加' : 'アプリを更新';
      final versionChange = installed == null
          ? '新規インストール'
          : '${installed.version} → ${incoming.version}';
      if (!await _confirm(action,
          'アプリ名: ${incoming.name}\n'
          'ID: ${incoming.id}\n'
          'バージョン: $versionChange\n'
          '権限: ${chappyPermissionsLabel(incoming.permissions)}\n\n'
          '${installed == null ? 'インストールしますか？' : '保存データを残して更新しますか？'}')) {
        return;
      }
      final app = await widget.repository.install(bytes);
      await widget.logs.add(app.id, 'info', 'import',
          'Installed version ${app.version}');
      if (mounted) setState(() {});
      _notify('${app.name} を登録しました');
    } catch (error) {
      await widget.logs.add('player', 'error', 'import', error.toString());
      _notify('インポート失敗: $error');
    } finally {
      if (mounted) setState(() => busy = false);
      if (_externalQueued && mounted) {
        unawaited(_consumeExternalChappy());
      }
    }
  }

  Future<void> _backupData() async {
    if (busy) { return; }
    setState(() => busy = true);
    try {
      final backup = DataBackupService(widget.repository.dataRoot);
      final bytes = await backup.exportData();
      final count = backup.inspect(bytes).appCount;
      if (count == 0) {
        throw const FormatException(
          'バックアップ対象の保存データがありません。先にメモ帳で保存してください。',
        );
      }
      if (!mounted) { return; }
      if (!await _confirm('保存データをバックアップ',
          '$count 個のアプリの保存データ（${bytes.length}バイト）を端末外に保存しますか？\n'
          '出力後に保存先のデータを読み戻して検証します。\n'
          'バックアップは暗号化されていません。安全な場所に保存してください。\n'
          'アプリ本体（.chappy）は含まれません。')) { return; }
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final receipt = await BackupExportService().export(
        bytes, fileName: 'chappy-data-$date.chappybackup',
      );
      if (receipt != null) {
        await widget.logs.add('player', 'info', 'backup',
            'Verified external backup: $count apps, ${receipt.sizeBytes} bytes');
        _notify('保存先の読み戻し検証に成功（${receipt.sizeBytes}バイト）。バックアップ完了！');
      }
    } catch (error) {
      await widget.logs.add('player', 'error', 'backup', error.toString());
      _notify('バックアップ失敗: $error');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> _restoreData() async {
    if (busy) { return; }
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any, withData: true,
      );
      if (result == null || result.files.isEmpty) { return; }
      final picked = result.files.single;
      if (!picked.name.toLowerCase().endsWith('.chappybackup')) {
        throw const FormatException('.chappybackup ファイルを選択してください');
      }
      final bytes = picked.bytes ?? (picked.path != null
          ? await FileBytes.read(picked.path!) : null);
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException(
          'バックアップファイルが0KBです。復元できません。'
          '元のメモ帳のデータは変更していません。',
        );
      }
      final backup = DataBackupService(widget.repository.dataRoot);
      final snapshot = backup.inspect(Uint8List.fromList(bytes));
      if (!mounted) { return; }
      final summary = snapshot.ids.take(6).join(', ');
      if (!await _confirm('保存データを復元',
          '${snapshot.appCount} 個のアプリの保存データを復元します。\n'
          '作成日時 (UTC): ${snapshot.createdAt}\n'
          '対象ID: $summary${snapshot.appCount > 6 ? ' ほか' : ''}\n\n'
          '同じIDの現在の保存データは上書きされます。'
          '復元前に現在のデータもバックアップしてください。')) { return; }
      final count = await backup.restore(Uint8List.fromList(bytes));
      await widget.logs.add('player', 'info', 'backup', 'Restored $count app data entries');
      _notify('$count 個のアプリの保存データを復元しました');
    } catch (error) {
      await widget.logs.add('player', 'error', 'backup', error.toString());
      _notify('復元失敗: $error');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> _menuAction(ChappyPackage app, String action) async {
    try {
      if (action == 'rollback') {
        if (!await widget.repository.canRollback(app.id)) {
          _notify('旧バージョンがありません');
          return;
        }
        if (!await _confirm('旧版に戻す', '保存データは残したまま、${app.name}の旧版へ切り替えますか？')) { return; }
        await widget.repository.rollback(app.id);
        await widget.logs.add(app.id, 'warning', 'rollback', 'Restored previous version');
        _notify('旧バージョンに戻しました');
      } else {
        final deleteData = action == 'delete_all';
        if (!await _confirm('アプリ削除', deleteData
            ? '${app.name} と保存データを完全に削除します。よろしいですか？'
            : '${app.name} の本体のみ削除します。保存データは残します。')) { return; }
        await widget.repository.remove(app.id, deleteData: deleteData);
        await widget.logs.add(app.id, 'warning', 'delete',
            'Deleted package, deleteData=$deleteData');
        _notify('削除しました');
      }
      if (mounted) { setState(() {}); }
    } catch (error) {
      _notify('操作失敗: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = widget.repository.apps;
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (context, snapshot) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chappy Player'),
              if (snapshot.hasData)
                Text(
                  'v${snapshot.data!.version} · Build ${snapshot.data!.buildNumber}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            key: const Key('home_data_menu'),
            tooltip: 'データ管理',
            enabled: !busy,
            icon: const Icon(Icons.folder_copy_outlined),
            onSelected: (action) {
              if (action == 'backup') {
                unawaited(_backupData());
              } else if (action == 'restore') {
                unawaited(_restoreData());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'backup',
                child: Row(children: [
                  Icon(Icons.save_alt_outlined),
                  SizedBox(width: 12),
                  Text('保存データをバックアップ'),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'restore',
                child: Row(children: [
                  Icon(Icons.settings_backup_restore),
                  SizedBox(width: 12),
                  Text('保存データを復元'),
                ]),
              ),
            ],
          ),
          IconButton(
            tooltip: 'プレイヤー本体の更新',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PlayerUpdatePage(
                logs: widget.logs,
              )),
            ),
            icon: const Icon(Icons.system_update_alt_outlined),
          ),
          IconButton(
            tooltip: 'Network Lab（LANサービス発見）',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NetworkLabPage(),
              ),
            ),
            icon: const Icon(Icons.lan_outlined),
          ),
          IconButton(
            tooltip: '端末セルフチェック',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => SelfCheckPage(
                repository: widget.repository,
                logs: widget.logs,
              )),
            ),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: '診断ログ',
            onPressed: () => Navigator.of(context).pushNamed('/logs'),
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('MY APPS', style: TextStyle(letterSpacing: 2, color: Colors.white60)),
        const SizedBox(height: 8),
        Text('アプリ ${apps.length} 個', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 22),
        if (apps.isEmpty) Card(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
          child: Column(children: [
            const Icon(Icons.apps_outlined, size: 52, color: Colors.white54),
            const SizedBox(height: 12),
            const Text('まだアプリがありません'),
            const SizedBox(height: 6),
            Text('公開ライブラリかファイルからミニアプリを追加してね',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
        ...apps.map((app) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: const CircleAvatar(child: Icon(Icons.extension_outlined)),
            title: Text(app.name),
            subtitle: Text('${app.id}\nv${app.version}', maxLines: 2),
            isThreeLine: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AppRunnerPage(
                app: app, repository: widget.repository, logs: widget.logs),
            )),
            trailing: PopupMenuButton<String>(
              tooltip: 'アプリ管理',
              onSelected: (value) => unawaited(_menuAction(app, value)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rollback', child: Text('旧版に戻す')),
                PopupMenuItem(value: 'delete_keep', child: Text('本体だけ削除')),
                PopupMenuItem(value: 'delete_all', child: Text('保存データも削除')),
              ],
            ),
          ),
        )),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ChappyCatalogPage(
              repository: widget.repository,
              logs: widget.logs,
              onLibraryChanged: () {
                if (mounted) {
                  setState(() {});
                }
              },
            )),
          ),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Chappy Apps 公開ライブラリ'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _import,
          icon: const Icon(Icons.add_circle_outline),
          label: Text(busy ? '処理中…' : '.chappy を追加 / 更新'),
        ),
        const SizedBox(height: 16),
        const Text('バックアップ・復元は右上の「データ管理」から。バックアップにアプリ本体は含まれません。',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 8),
        const Text('オフライン専用の個人向けプレイヤー。信頼できる自作パッケージのみ読み込んでください。',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
      ])),
    );
  }
}

/// Lazy file read for Android pickers that return an on-device cache path.
class FileBytes {
  static Future<Uint8List> read(String path) async {
    final file = File(path);
    if (await file.length() > 12 * 1024 * 1024) {
      throw const FormatException('ファイルが大きすぎます');
    }
    return file.readAsBytes();
  }
}
