import 'package:chappy_player/core/pc_identity_client.dart';
import 'package:chappy_player/screens/verified_pc_history_page.dart';
import 'package:flutter/material.dart';

/// Host-only device identity management, NOT a paired-PC list.
///
/// Creating this key alone authorizes NOTHING on the LAN. The app still
/// requires explicit, pinned-TLS QR mutual authentication in a later stage.
class PcIdentityPage extends StatefulWidget {
  final PcIdentityClient client;

  const PcIdentityPage({
    super.key,
    this.client = const PcIdentityClient(),
  });

  @override
  State<PcIdentityPage> createState() => _PcIdentityPageState();
}

class _PcIdentityPageState extends State<PcIdentityPage> {
  PcIdentityStatus? _identity;
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
      final current = await widget.client.status();
      if (!mounted || generation != _generation) return;
      setState(() => _identity = current);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '端末キーを確認できません: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() async {
    if (_busy || _identity?.created != false) return;
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('この端末の接続用キーを作成'),
        content: const Text(
          'Android KeyStoreに端末専用の秘密鍵を作ります。'
          '秘密鍵は取り出せず、鍵を作るだけではPCとの接続や遠隔操作は許可されません。'
          '今後ペアリングする前に双方の確認が別途必要です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('端末キーを作成'),
          ),
        ],
      ),
    );
    if (!mounted || consent != true || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.client.create();
      if (!mounted || generation != _generation) return;
      setState(() => _identity = created);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '作成できませんでした: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revoke() async {
    final fingerprint = _identity?.fingerprint;
    if (_busy || _identity?.created != true || fingerprint == null) return;
    final confirmationGeneration = _generation;
    final suffix = fingerprint.substring(fingerprint.length - 8);
    var entered = '';
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, updateDialog) => AlertDialog(
          title: const Text('この端末のキーを削除'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android KeyStoreの秘密鍵を完全に削除します。'
                '元の鍵は復元できず、作り直すと公開鍵指紋が変わります。'
                'このスマホに保存した確認済みPCの暗号化履歴も消去されます。'
                'Windows側の記録・秘密鍵は変更せず、'
                '相手PCへの失効通知も送られません。'
                'PC側の古い記録はPCで別途確認・削除してください。',
              ),
              const SizedBox(height: 12),
              Text('確認用：公開鍵指紋の末尾8文字「$suffix」'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pc_identity_revoke_suffix'),
                maxLength: 8,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '末尾8文字を正確に入力',
                  helperText: '入力が一致するまで削除できません',
                ),
                onChanged: (value) =>
                    updateDialog(() => entered = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('削除しない'),
            ),
            FilledButton(
              key: const Key('pc_identity_revoke_confirm'),
              onPressed: entered == suffix
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('秘密鍵を削除'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || consent != true || _busy ||
        confirmationGeneration != _generation ||
        _identity?.fingerprint != fingerprint) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The Android native host must also compare the exact fingerprint
      // before deleting, so stale UI consent can never revoke a new key.
      final removed = await widget.client.revoke(fingerprint);
      if (!mounted || generation != _generation) return;
      if (!removed) {
        throw StateError('秘密鍵が存在しません');
      }
      final next = await widget.client.status();
      if (!mounted || generation != _generation) return;
      setState(() => _identity = next);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      // The native key may already have been deleted when encrypted history
      // cleanup reports an error. Re-read the actual state, never display
      // an old public fingerprint as if the key still existed.
      try {
        final current = await widget.client.status();
        if (!mounted || generation != _generation) return;
        setState(() => _identity = current);
      } catch (_) {
        // Keep the original failure visible; user may refresh/recover.
      }
      if (!mounted || generation != _generation) return;
      setState(() => _error =
          '端末キーの削除結果を確認してください。操作エラー: $error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _identity;
    return Scaffold(
      appBar: AppBar(title: const Text('PC連携用の端末キー（準備）')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '安全なPCペアリングのための鍵を準備します。',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'ここでは端末キーの作成・確認・削除と、'
              'QR-v3で検証したPCの履歴を管理できます。'
              '鍵や確認履歴だけでは、永続的なペアリング、'
              '自動接続、通信監視、ファイル転送、遠隔操作はできません。',
            ),
            const SizedBox(height: 18),
            Text(
              status == null
                  ? '状態を確認しています'
                  : status.created ? 'Android端末キー：作成済み' : 'Android端末キー：未作成',
              key: const Key('pc_identity_status'),
            ),
            if (status?.fingerprint != null) ...[
              const SizedBox(height: 12),
              const Text('公開鍵のSHA-256指紋（秘密鍵ではありません）'),
              SelectableText(
                status!.fingerprint!,
                key: const Key('pc_identity_fingerprint'),
              ),
            ],
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              SelectableText(
                _error!,
                key: const Key('pc_identity_error'),
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('pc_identity_create'),
              onPressed: !_busy && status?.created == false ? _create : null,
              icon: const Icon(Icons.key_outlined),
              label: const Text('端末キーを作成'),
            ),
            OutlinedButton.icon(
              key: const Key('pc_identity_revoke'),
              onPressed: !_busy && status?.created == true ? _revoke : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('この端末の秘密鍵を削除'),
            ),
            OutlinedButton.icon(
              key: const Key('pc_verified_history_open'),
              onPressed: _busy || status?.created != true
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const VerifiedPcHistoryPage(),
                        ),
                      ),
              icon: const Icon(Icons.devices_other_outlined),
              label: const Text('確認済みPCの記録を確認・削除'),
            ),
            TextButton.icon(
              key: const Key('pc_identity_refresh'),
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('状態を更新'),
            ),
          ],
        ),
      ),
    );
  }
}
