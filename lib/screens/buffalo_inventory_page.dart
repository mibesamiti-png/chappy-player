import 'package:chappy_player/core/buffalo_client_inventory.dart';
import 'package:flutter/material.dart';

/// BUFFALO first-stage offline client inventory: no admin login or router
/// scrape until the actual router model/API is confirmed.
class BuffaloInventoryPage extends StatefulWidget {
  const BuffaloInventoryPage({super.key});

  @override
  State<BuffaloInventoryPage> createState() => _BuffaloInventoryPageState();
}

class _BuffaloInventoryPageState extends State<BuffaloInventoryPage>
    with WidgetsBindingObserver {
  final _source = TextEditingController();
  final _knownMacs = <String>{};
  List<RouterInventoryEntry> _devices = const [];
  String? _error;
  bool _routerOwner = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    _source.clear();
    _devices = const [];
    _knownMacs.clear();
    _error = null;
    _routerOwner = false;
    _loaded = false;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _source.clear();
    _knownMacs.clear();
    _devices = const [];
    _source.dispose();
    super.dispose();
  }

  void _import() {
    if (!_routerOwner) return;
    try {
      final found = BuffaloClientInventoryParser.parse(_source.text);
      setState(() {
        _knownMacs.clear();
        _devices = found;
        _loaded = true;
        _error = found.isEmpty
            ? 'IPアドレスまたはMACアドレスを含む行が見つかりませんでした。'
            : null;
      });
    } on FormatException catch (e) {
      setState(() {
        _devices = const [];
        _knownMacs.clear();
        _loaded = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unknown = _devices
        .where((d) => d.mac == null || !_knownMacs.contains(d.mac))
        .length;
    final devices = [
      ..._devices.where((d) => d.mac == null || !_knownMacs.contains(d.mac)),
      ..._devices.where((d) => d.mac != null && _knownMacs.contains(d.mac)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('BUFFALO 端末一覧')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('ルーター接続機器の確認',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'この機能はBUFFALO管理画面から自分でコピーした端末一覧を'
              'オフラインで整理する試作版です。'
              '端末側のアプリ登録やペアリングは不要です。'
              'ルーターへの自動ログイン・通信先の自動取得はまだ対応していません。',
            ),
            const SizedBox(height: 12),
            const Text(
              'AirStationアプリまたは管理画面で「デバイスコントロール」'
              '「ステータス → クライアントモニター」などを開き、'
              '表示されたIP・MACアドレスを1行1端末でコピーしてください。'
              '型番によって画面や表示項目は異なります。',
            ),
            const SizedBox(height: 12),
            const Text(
              '入力例（サンプルのアドレス）：\n'
              '192.168.11.10, AA:BB:CC:DD:EE:01, MyPhone\n'
              '192.168.11.12, AA:BB:CC:DD:EE:02, UnknownDevice\n'
              'MACアドレスだけの行にも対応します。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('buffalo_inventory_input'),
              controller: _source,
              maxLines: 6,
              minLines: 4,
              maxLength: BuffaloClientInventoryParser.maxInputLength,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '管理画面からコピーした端末一覧',
                border: OutlineInputBorder(),
                hintText: '192.168.11.10, AA:BB:CC:DD:EE:01, MyPhone',
              ),
            ),
            CheckboxListTile(
              key: const Key('buffalo_owner_consent'),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('自分が管理するBUFFALOルーターの一覧を読み込みます'),
              value: _routerOwner,
              onChanged: (value) =>
                  setState(() => _routerOwner = value == true),
            ),
            FilledButton.icon(
              key: const Key('buffalo_inventory_import'),
              onPressed: _routerOwner ? _import : null,
              icon: const Icon(Icons.list_alt),
              label: const Text('コピーした一覧を解析'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('buffalo_inventory_clear'),
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('一覧と登録状態を消去'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('buffalo_inventory_error'),
                  style: const TextStyle(color: Colors.orangeAccent)),
            ],
            if (_loaded) ...[
              const SizedBox(height: 16),
              Text('取得データ内 ${_devices.length}台／未登録 $unknown 台',
                  key: const Key('buffalo_inventory_counts'),
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '「未登録」はこの画面内で確認済みにしていないという意味です。'
                '不正アクセス端末という判定ではありません。'
                'スマホのMACランダム化やIP変更にも注意してください。',
                style: TextStyle(fontSize: 12),
              ),
              for (final device in devices)
                Card(
                  child: ListTile(
                    leading: Icon(
                      device.mac != null && _knownMacs.contains(device.mac)
                          ? Icons.verified_outlined
                          : Icons.help_outline,
                    ),
                    title: Text(
                        device.hostname ?? device.ip ?? device.mac ?? '名称不明'),
                    subtitle: Text(
                      '${device.ip ?? "IP不明"}\n'
                      '${device.mac ?? "MAC不明（識別の確実性が低い）"}\n'
                      '${device.mac != null && _knownMacs.contains(device.mac) ? "確認済み" : "未登録・要確認"}',
                    ),
                    isThreeLine: true,
                    trailing: device.mac == null
                        ? null
                        : TextButton(
                            key: Key('buffalo_known_${device.identity}'),
                            onPressed: () => setState(() {
                              if (!_knownMacs.add(device.mac!)) {
                                _knownMacs.remove(device.mac);
                              }
                            }),
                            child: Text(_knownMacs.contains(device.mac)
                                ? '未登録に戻す'
                                : '既知にする'),
                          ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            const Text(
              'これはルーター側に表示された機器の「一覧」を扱うだけで、'
              '通信先IPやアプリ名を収集する機能ではありません。'
              '一覧はこの画面のメモリ内だけに保持し、背景化・終了時に破棄します。'
              '自動接続機能はBUFFALOの正確な型番・APIが確認できてから検討します。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
