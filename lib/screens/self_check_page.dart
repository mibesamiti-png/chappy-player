import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/core/self_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SelfCheckPage extends StatefulWidget {
  final PackageRepository repository;
  final LogStore logs;

  const SelfCheckPage({
    super.key,
    required this.repository,
    required this.logs,
  });

  @override
  State<SelfCheckPage> createState() => _SelfCheckPageState();
}

class _SelfCheckPageState extends State<SelfCheckPage> {
  List<SelfCheckResult>? _results;
  bool _running = false;
  String? _fatal;

  Future<void> _runChecks() async {
    if (_running) return;
    setState(() {
      _running = true;
      _fatal = null;
    });
    try {
      final results = await SelfCheckService(
        repository: widget.repository,
        logs: widget.logs,
      ).run();
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _fatal = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copyReport() async {
    final items = _results;
    if (items == null) return;
    await Clipboard.setData(ClipboardData(
      text: SelfCheckService.report(items),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('診断結果をコピーしました。共有前に内容を確認してください'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final passed = results?.where((item) => item.passed).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('端末セルフチェック'),
        actions: [
          IconButton(
            tooltip: '結果をコピー',
            onPressed: results == null || _running ? null : _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('プレイヤーの動作診断',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          const Text(
            'スマホの保存処理、インストール済みアプリ、ローカルサーバー、'
            'ログファイルを確認します。外部のサーバーへデータは送信しません。',
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _running ? null : _runChecks,
            icon: _running
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text(_running ? '診断中…' : 'セルフチェックを実行'),
          ),
          if (_fatal != null) ...[
            const SizedBox(height: 12),
            SelectableText('診断を実行できませんでした: $_fatal'),
          ],
          if (results != null) ...[
            const SizedBox(height: 18),
            Text('結果: $passed / ${results.length} 項目成功',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final item in results)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.passed
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: item.passed ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  title: Text(item.label),
                  subtitle: SelectableText(
                    '${item.detail}\n${item.elapsedMs} ms',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
          const SizedBox(height: 20),
          const Text(
            'このチェックはWebView実描画、カメラ、マイク、'
            'AndroidのAPK署名更新までは検証しません。'
            '実機テストで問題が出た場合は、結果と診断ログを添えて報告してください。',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ]),
      ),
    );
  }
}
