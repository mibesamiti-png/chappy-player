import 'package:chappy_player/core/router_identity_client.dart';
import 'package:flutter/material.dart';

/// Router candidate identification without passwords or model pre-entry.
/// UPnP device names and makers are self-advertised hints, not verified facts.
class RouterAutoIdentifyPage extends StatefulWidget {
  final RouterIdentityClient client;

  const RouterAutoIdentifyPage({
    super.key,
    this.client = const RouterIdentityClient(),
  });

  @override
  State<RouterAutoIdentifyPage> createState() => _RouterAutoIdentifyPageState();
}

class _RouterAutoIdentifyPageState extends State<RouterAutoIdentifyPage>
    with WidgetsBindingObserver {
  RouterIdentitySnapshot? _snapshot;
  bool _ownerApproved = false;
  bool _foreground = true;
  bool _busy = false;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _discard() {
    _generation++;
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _ownerApproved = false;
      _busy = false;
      _message = '結果を破棄しました。';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _foreground = false;
      _discard();
    } else {
      _foreground = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _snapshot = null;
    super.dispose();
  }

  Future<void> _identify() async {
    if (_busy || !_foreground || !_ownerApproved ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final approvalGeneration = _generation;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('接続中のルーター候補を調べますか？'),
        content: const Text(
          'Androidが保持する現在のWi-FiのゲートウェイIPを読み取ります。'
          'さらにLANへUPnP機器発見用のSSDP問い合わせを1回だけ送り、'
          '応答がゲートウェイと一致した場合に限って公開の機器説明XMLを'
          '最大16KiB読み取ります。処理は数秒で終了します。\n\n'
          'ログイン情報やパスワードは使いません。'
          '接続先の閲覧履歴、他の端末の通信内容や一覧は取得しません。'
          '検出したメーカー・型番は機器の自己申告なので確定ではありません。'
          '取得結果はこの画面内だけで表示し保存しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('今回だけ識別する'),
          ),
        ],
      ),
    );
    if (!mounted || !_foreground || !_ownerApproved ||
        approvalGeneration != _generation || confirmed != true) {
      return;
    }

    final request = ++_generation;
    setState(() {
      _busy = true;
      _snapshot = null;
      _message = null;
    });
    try {
      final info = await widget.client.probe();
      if (!mounted || !_foreground || _generation != request) return;
      setState(() {
        _snapshot = info;
        _message = info.hasAdvertisedIdentity
            ? 'UPnPで機器が申告したモデル候補を表示しました。'
            : 'Wi-Fiのゲートウェイは確認できましたが、機種名は取得できませんでした。';
      });
    } catch (_) {
      if (mounted && _foreground && _generation == request) {
        setState(() {
          _message = 'ルーター候補を取得できませんでした。'
              'Wi-Fi接続、VPNの状態、Androidのローカルネットワーク制限を確認してください。';
        });
      }
    } finally {
      if (mounted && _generation == request) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('ルーター自動識別')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Wi-Fiルーターの型番候補を探す',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            const Text(
              '型番を入力する必要はありません。'
              'このスマホが接続中のWi-Fiから、ルーターと思われる'
              'ゲートウェイと、機器が公開するUPnPモデル名を探します。',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const Key('router_id_owner'),
              value: _ownerApproved,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('自分が管理するWi-Fiネットワークで実行する'),
              onChanged: _busy ? null : (value) =>
                  setState(() => _ownerApproved = value == true),
            ),
            FilledButton.icon(
              key: const Key('router_id_start'),
              onPressed: _busy || !_ownerApproved || !_foreground
                  ? null : _identify,
              icon: const Icon(Icons.router_outlined),
              label: const Text('ルーターを自動識別'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('router_id_clear'),
              onPressed: _discard,
              icon: const Icon(Icons.delete_outline),
              label: const Text('結果を破棄'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(key: Key('router_id_busy')),
              const Text('Wi-FiのゲートウェイとUPnPの公開情報を確認しています'),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('router_id_status')),
            ],
            if (router != null) ...[
              const SizedBox(height: 14),
              Text('確認結果',
                  style: Theme.of(context).textTheme.titleMedium),
              Card(
                child: Column(children: [
                  ListTile(
                    title: const Text('現在のデフォルトゲートウェイ'),
                    subtitle: SelectableText(
                      router.gatewayIpv4,
                      key: const Key('router_id_gateway'),
                    ),
                  ),
                  ListTile(
                    title: const Text('型番候補'),
                    subtitle: Text(router.modelName ??
                        router.modelNumber ?? '取得できませんでした',
                        key: const Key('router_id_model')),
                  ),
                  if (router.modelNumber != null && router.modelName != null)
                    ListTile(
                      title: const Text('モデル番号（自己申告）'),
                      subtitle: Text(router.modelNumber!),
                    ),
                  ListTile(
                    title: const Text('メーカー候補'),
                    subtitle: Text(router.manufacturer ?? '不明',
                        key: const Key('router_id_manufacturer')),
                  ),
                  if (router.friendlyName != null)
                    ListTile(
                      title: const Text('機器が申告した名前'),
                      subtitle: Text(router.friendlyName!),
                    ),
                  ListTile(
                    title: const Text('根拠'),
                    subtitle: Text(router.evidence == 'upnp_self_report'
                        ? 'AndroidのWi-Fi経路 + ゲートウェイのUPnP自己申告'
                        : 'AndroidのWi-Fi経路のみ（機種情報なし）'),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              '注意：デフォルトゲートウェイがBUFFALO本体とは限りません。'
              'BUFFALOがブリッジ/APモードなら上流ルーターが表示されます。'
              'UPnP無効・機種非対応なら型番不明になります。'
              '自己申告の型番は実機ラベルや公式AirStationアプリで'
              '確認してから、機種別機能に使います。',
            ),
            const SizedBox(height: 8),
            const Text(
              'これは接続端末一覧や他の端末の通信先を自動的に'
              '読み取る機能ではありません。'
              '端末一覧の確認にはNetwork LabのBUFFALO端末一覧を利用できます。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
