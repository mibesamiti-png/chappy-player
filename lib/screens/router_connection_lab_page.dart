import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/core/openwrt_router_client.dart';
import 'package:chappy_player/core/router_connection_snapshot.dart';
import 'package:flutter/material.dart';

/// Explicit, one-action OpenWrt read-only connection inspector.
/// Router authentication is native Flutter host ONLY, never .chappy JS.
/// No IP discovery sweep, traffic capture, history, export or background loop.
class RouterConnectionLabPage extends StatefulWidget {
  final LanDiscoveryClient wifiClient;
  const RouterConnectionLabPage({
    super.key,
    this.wifiClient = const LanDiscoveryClient(),
  });

  @override
  State<RouterConnectionLabPage> createState() =>
      _RouterConnectionLabPageState();
}

class _RouterConnectionLabPageState extends State<RouterConnectionLabPage>
    with WidgetsBindingObserver {
  final _routerIp = TextEditingController();
  final _routerPort = TextEditingController(text: '443');
  final _certificatePin = TextEditingController();
  final _deviceIp = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  OpenWrtRouterClient? _activeClient;
  RouterConnectionSnapshot? _snapshot;
  bool _ownerApproved = false;
  bool _busy = false;
  bool _attempted = false;
  bool _foreground = true;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _wipe({bool resetAttempt = false}) {
    _generation++;
    _activeClient?.cancel();
    _activeClient = null;
    _password.clear();
    _snapshot = null;
    _ownerApproved = false;
    if (resetAttempt) _attempted = false;
    if (mounted) setState(() => _busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _foreground = false;
      _wipe();
      // Forget router/target identifiers and account on background/lock.
      _routerIp.clear();
      _routerPort.text = '443';
      _certificatePin.clear();
      _deviceIp.clear();
      _username.clear();
      if (mounted) {
        setState(() => _error = '背景化したため、認証情報と結果を破棄しました');
      }
    } else {
      _foreground = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _activeClient?.cancel();
    _routerIp.dispose();
    _routerPort.dispose();
    _certificatePin.dispose();
    _deviceIp.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<bool> _wifiAllowed() async {
    if (!_foreground || !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    return widget.wifiClient.trafficPairingAllowed();
  }

  Future<void> _load() async {
    if (_busy || _attempted || !_foreground || !_ownerApproved ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final routerIp = _routerIp.text.trim();
    final deviceIp = _deviceIp.text.trim();
    final port = int.tryParse(_routerPort.text.trim()) ?? -1;
    final fp = _certificatePin.text.trim().toLowerCase();
    final username = _username.text;
    final password = _password.text;
    try {
      OpenWrtRouterClient.validateRouter(
        ip: routerIp, port: port, tlsFingerprint: fp,
        deviceIp: deviceIp, username: username, password: password,
      );
    } catch (_) {
      setState(() => _error =
          '管理ルーターのIPv4/HTTPSポート/証明書指紋と許可済み端末IPを確認してください');
      return;
    }
    final approval = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('ルーター接続先の情報を1回だけ読み取りますか？'),
        content: Text(
          '対象: $deviceIp\nルーター: $routerIp:$port\n\n'
          '本人が管理するOpenWrtルーターにHTTPSで接続し、'
          'TLS証明書SHA-256を照合した後、認証済みLuCI APIから'
          '指定IPの現在の接続先IP・ポート・通信方式だけを取得します。\n\n'
          '対象端末の所有者または管理者の許可が必要です。'
          '接続先IPは機微な情報です。保存/外部送信/バックグラウンド取得は行いません。'
          '特権をミニアプリへ渡しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('今回だけ取得する'),
          ),
        ],
      ),
    );
    if (!mounted || approval != true || !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final request = ++_generation;
    final client = OpenWrtRouterClient();
    _activeClient = client;
    setState(() {
      _attempted = true;
      _busy = true;
      _snapshot = null;
      _error = null;
    });
    try {
      final result = await client.readOnce(
        routerIp: routerIp, port: port, tlsFingerprint: fp,
        deviceIp: deviceIp, username: username, password: password,
        approvedWifi: _wifiAllowed,
      ).timeout(const Duration(seconds: 60));
      if (!mounted || request != _generation || !_foreground ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      setState(() => _snapshot = result);
    } catch (_) {
      if (mounted && request == _generation) {
        setState(() => _error =
            '取得できませんでした。ルーターのHTTPS指紋、LuCI rpcd権限、'
            '端末IP、Wi-Fi/VPN状態を確認してください。パスワードは破棄しました。');
      }
    } finally {
      client.cancel();
      _password.clear(); // Never retain admin password on successful login.
      if (mounted && request == _generation) {
        setState(() {
          _busy = false;
          _activeClient = null;
          _ownerApproved = false;
        });
      }
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboard,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: hint,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Router Connection Lab')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('管理ルーターの接続先確認（OpenWrt試作）',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'ルーターが現在保持する通信セッションのメタデータだけを表示します。'
            'これはルーターに対応APIがある場合の機能です。'
            '一般の家庭用ルーターで必ず使えるわけではありません。',
          ),
          const SizedBox(height: 16),
          _field(label: 'OpenWrtルーター IPv4', controller: _routerIp,
              hint: '192.168.1.1',
              keyboard: TextInputType.number),
          _field(label: 'HTTPSポート', controller: _routerPort,
              keyboard: TextInputType.number),
          _field(label: 'ルーター証明書 SHA-256（64桁）',
              controller: _certificatePin,
              hint: 'ルーター管理画面などで別経路から確認'),
          _field(label: '接続先を調べる許可済み端末のIPv4',
              controller: _deviceIp, hint: '192.168.1.20',
              keyboard: TextInputType.number),
          _field(label: 'LuCI / rpcd 読み取り権限のユーザー名',
              controller: _username),
          _field(label: 'LuCI / rpcd パスワード',
              controller: _password, secret: true),
          const Text(
            'ルーター管理者は可能ならgetDHCPLeasesとgetConntrackList'
            'のみ許可した専用の読み取りアカウントを使用してください。'
            'パスワード、接続先一覧、セッショントークンは保存しません。',
            style: TextStyle(fontSize: 12),
          ),
          CheckboxListTile(
            value: _ownerApproved,
            onChanged: _busy ? null : (v) =>
                setState(() => _ownerApproved = v == true),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('このルーターを管理し、対象端末の情報取得について許可を得ています'),
          ),
          FilledButton.icon(
            key: const Key('router_once_read'),
            onPressed: _busy || _attempted || !_ownerApproved ? null : _load,
            icon: const Icon(Icons.router_outlined),
            label: const Text('HTTPS接続して今回だけ読み取る'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const Key('router_reset'),
            onPressed: _busy ? null : () {
              _wipe(resetAttempt: true);
              _error = null;
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('結果・承認を消去して新しい取得を準備'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const Text('ルーターのHTTPS認証と接続表を確認中…'),
            OutlinedButton(
              onPressed: () => _wipe(),
              child: const Text('接続を中止'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, key: const Key('router_error'),
                  style: const TextStyle(color: Colors.orangeAccent)),
            ),
          if (snapshot != null) ...[
            const SizedBox(height: 18),
            Text(
              snapshot.deviceName == null
                  ? '対象端末: ${snapshot.deviceIp}'
                  : '対象端末: ${snapshot.deviceName} (${snapshot.deviceIp})',
              key: const Key('router_device_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('現在の接続先 ${snapshot.connections.length}件'
                '${snapshot.truncated ? '（上限120件まで表示）' : ''}',
                key: const Key('router_connection_count')),
            if (snapshot.connections.isEmpty)
              const Text('対象IPの接続は観測されませんでした。'
                  'ルーターや通信経路によって記録されない場合もあります。'),
            for (final (index, connection)
                in snapshot.connections.indexed)
              Card(child: ListTile(
                leading: const Icon(Icons.alt_route_outlined),
                title: Text(connection.destinationIp,
                    key: Key('router_dest_$index')),
                subtitle: Text(
                    '${connection.protocol} / port ${connection.destinationPort}'),
              )),
            const SizedBox(height: 8),
            const Text('IPだけでアプリ名・閲覧サイト・通信内容は断定できません。'
                'VPN・Private DNS・DoHやIPv6経路によって表示が欠けることがあります。'),
          ],
          const SizedBox(height: 18),
          const Text(
            'この試作は、本人管理のOpenWrt HTTPS/ubusに限定。'
            '平文HTTP・未確認証明書へのパスワード送信・'
            '接続先の継続監視・他人端末の無断閲覧はしません。'
            'アプリを背景にすると接続と結果を消去します。',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      )),
    );
  }
}
