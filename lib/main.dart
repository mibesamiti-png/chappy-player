import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:chappy_player/core/data_backup_service.dart';
import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/screens/app_runner_page.dart';
import 'package:chappy_player/screens/logs_page.dart';
import 'package:chappy_player/screens/self_check_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
    if (busy) { return; }
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) { return; }
      final picked = result.files.single;
      if (!picked.name.toLowerCase().endsWith('.chappy')) {
        _notify('.chappyファイルを選択してください');
        return;
      }
      final bytes = picked.bytes ?? (picked.path != null
          ? await FileBytes.read(picked.path!) : null);
      if (bytes == null) { throw const FormatException('選択したファイルを読み取れませんでした'); }
      if (bytes.length > 12 * 1024 * 1024) {
        throw const FormatException('ファイルサイズが上限（12MiB）を超えています');
      }
      // Inspect before displaying the confirmation dialog. The source file
      // name is not a trusted app identity.
      final incoming = widget.repository.inspect(Uint8List.fromList(bytes));
      final matches = widget.repository.apps.where((a) => a.id == incoming.id);
      final installed = matches.isEmpty ? null : matches.first;
      if (!mounted) { return; }
      setState(() => busy = true);
      final action = installed == null ? 'アプリを追加' : 'アプリを更新';
      final versionChange = installed == null
          ? '新規インストール'
          : '${installed.version} → ${incoming.version}';
      if (!await _confirm(action,
          'アプリ名: ${incoming.name}\n'
          'ID: ${incoming.id}\n'
          'バージョン: $versionChange\n'
          '権限: 追加権限なし\n\n'
          '${installed == null ? 'インストールしますか？' : '保存データを残して更新しますか？'}')) {
        return;
      }
      final app = await widget.repository.install(Uint8List.fromList(bytes));
      await widget.logs.add(app.id, 'info', 'import', 'Installed version ${app.version}');
      if (mounted) { setState(() {}); }
      _notify('${app.name} を登録しました');
    } catch (error) {
      await widget.logs.add('player', 'error', 'import', error.toString());
      _notify('インポート失敗: $error');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  /// Make the first Android test possible without downloading any external file.
  Future<void> _installBundledSample() async {
    if (busy) { return; }
    setState(() => busy = true);
    try {
      final asset = await rootBundle.load('sample_memo.chappy');
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes, asset.lengthInBytes,
      );
      final incoming = widget.repository.inspect(bytes);
      final matches = widget.repository.apps.where((a) => a.id == incoming.id);
      final installed = matches.isEmpty ? null : matches.first;
      if (!mounted) { return; }
      final change = installed == null
          ? '新規インストール'
          : '${installed.version} → ${incoming.version}';
      if (!await _confirm('サンプルメモ帳',
          '${incoming.name}\n'
          'ID: ${incoming.id}\n'
          'バージョン: $change\n\n'
          '${installed == null ? 'サンプルアプリを追加しますか？' : '既存のアプリ本体を上書きしますか？ 保存データは保持します。'}')) {
        return;
      }
      final app = await widget.repository.install(bytes);
      await widget.logs.add(app.id, 'info', 'sample', 'Installed bundled sample ${app.version}');
      if (mounted) { setState(() {}); }
      _notify('${app.name} を追加しました。タップして起動してね');
    } catch (error) {
      await widget.logs.add('player', 'error', 'sample', error.toString());
      _notify('サンプルの追加に失敗しました: $error');
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> _backupData() async {
    if (busy) { return; }
    setState(() => busy = true);
    try {
      final backup = DataBackupService(widget.repository.dataRoot);
      final bytes = await backup.exportData();
      final count = backup.inspect(bytes).appCount;
      if (!mounted) { return; }
      if (!await _confirm('保存データをバックアップ',
          '$count 個のアプリの保存データを端末外に保存しますか？\n'
          'バックアップは暗号化されていません。安全な場所に保存してください。\n'
          'アプリ本体（.chappy）は含まれません。')) { return; }
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Chappy保存データを保存',
        fileName: 'chappy-data-$date.chappybackup',
        type: FileType.any,
        bytes: bytes,
      );
      if (result != null) {
        await widget.logs.add('player', 'info', 'backup', 'Exported $count app data entries');
        _notify('保存データのバックアップを作成しました');
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
      if (bytes == null) {
        throw const FormatException('バックアップを読み取れませんでした');
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
        title: const Text('Chappy Player'),
        actions: [
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
            Text('まず sample_memo.chappy を追加してね',
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
        FilledButton.tonalIcon(
          onPressed: busy ? null : _installBundledSample,
          icon: const Icon(Icons.science_outlined),
          label: const Text('サンプルメモ帳を追加してテスト'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _import,
          icon: const Icon(Icons.add_circle_outline),
          label: Text(busy ? '処理中…' : '.chappy を追加 / 更新'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _backupData,
          icon: const Icon(Icons.save_alt_outlined),
          label: const Text('保存データをバックアップ'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _restoreData,
          icon: const Icon(Icons.settings_backup_restore),
          label: const Text('保存データを復元'),
        ),
        const SizedBox(height: 16),
        const Text('バックアップにはアプリ本体が含まれません。重要なデータは必ず端末外に保管してください。',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 8),
        const Text('v0.1 試作版｜オフライン専用。信頼できる自作パッケージのみ読み込んでください。',
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
