import 'package:chappy_player/core/verified_pc_history_client.dart';
import 'package:flutter/material.dart';

/// User-visible local QR-v3 verification history, NOT paired-device access.
class VerifiedPcHistoryPage extends StatefulWidget {
  final VerifiedPcHistoryClient client;

  const VerifiedPcHistoryPage({
    super.key,
    this.client = const VerifiedPcHistoryClient(),
  });

  @override
  State<VerifiedPcHistoryPage> createState() => _VerifiedPcHistoryPageState();
}

class _VerifiedPcHistoryPageState extends State<VerifiedPcHistoryPage> {
  List<VerifiedPcRecord>? _records;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.list();
      if (!mounted || generation != _generation) return;
      setState(() => _records = result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '履歴を読み取れません: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _forget(String fingerprint) async {
    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('PCの確認履歴を削除'),
        content: Text(
          'このPCの公開鍵指紋をスマホ内の記録から削除しますか？\n'
          '$fingerprint\n\n'
          'PC本体の設定や秘密鍵は変更しません。'
          '再接続には引き続き新しいQRでの認証が必要です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('削除しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('この記録を削除'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.forget(fingerprint);
      if (!mounted || generation != _generation) return;
      setState(() => _records = result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '削除できませんでした: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('確認済みPCの記録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'QR-v3で本人確認に成功し、保存を承認したPCの公開鍵指紋です。',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'この記録は端末内の暗号化されたメモです。'
              '現在接続していることや、次回の自動接続・PC操作を'
              '許可したことを意味しません。'
              'PC側の登録・解除情報ともまだ同期していません。',
            ),
            const SizedBox(height: 14),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              SelectableText(
                _error!,
                key: const Key('verified_pc_error'),
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const Key('verified_pc_refresh'),
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('確認履歴を更新'),
            ),
            if (records != null && records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  '保存したPCはありません。',
                  key: Key('verified_pc_empty'),
                ),
              ),
            if (records != null)
              for (final record in records)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PC公開鍵SHA-256'),
                        const SizedBox(height: 6),
                        SelectableText(
                          record.fingerprint,
                          key: Key('verified_pc_${record.fingerprint}'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '保存日時: ${DateTime.fromMillisecondsSinceEpoch(record.addedUnix * 1000).toLocal()}',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _forget(record.fingerprint),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('記録を削除'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
