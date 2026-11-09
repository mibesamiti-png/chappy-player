import 'dart:async';

import 'package:chappy_player/core/lan_discovery_client.dart';
import 'package:chappy_player/screens/companion_pairing_page.dart';
import 'package:chappy_player/screens/browser_page.dart';
import 'package:chappy_player/screens/network_diagnostic_page.dart';
import 'package:chappy_player/screens/device_traffic_page.dart';
import 'package:chappy_player/screens/remote_traffic_import_page.dart';
import 'package:chappy_player/screens/pc_identity_page.dart';
import 'package:chappy_player/core/companion_pairing_client.dart';
import 'package:flutter/material.dart';

/// Trusted host UI: never grants arbitrary mini-apps LAN discovery or access.
class NetworkLabPage extends StatefulWidget {
  final LanDiscoveryClient client;

  const NetworkLabPage({
    super.key,
    this.client = const LanDiscoveryClient(),
  });

  @override
  State<NetworkLabPage> createState() => _NetworkLabPageState();
}

class _NetworkLabPageState extends State<NetworkLabPage>
    with WidgetsBindingObserver {
  String _serviceType = '_http._tcp.';
  LanDiscoverySnapshot? _snapshot;
  Timer? _pollTimer;
  String? _error;
  bool _busy = false;
  int _epoch = 0;

  bool get _scanning => _snapshot?.running == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelScan(clearResults: true);
    }
  }

  void _cancelScan({required bool clearResults}) {
    _epoch++;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(widget.client.stop());
    if (clearResults && mounted) {
      setState(() {
        _snapshot = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelScan(clearResults: false);
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _scanning) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('LANサービスの発見'),
        content: const Text(
          'この操作では、今接続しているWi-Fiなどのローカルネットワークから、'
          '機器が公開しているサービスの名前やIPアドレスを探します。\n\n'
          '探索は15秒で自動終了し、端末の外には保存・送信しません。'
          '他の機器の通信内容は取得しません。'
          '自分が管理するネットワークでのみ実行してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('15秒間だけ探す'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;

    final request = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _snapshot = null;
    });
    try {
      final result = await widget.client.start(_serviceType);
      if (!mounted || request != _epoch) {
        unawaited(widget.client.stop());
        return;
      }
      setState(() => _snapshot = result);
      if (result.running) {
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          unawaited(_refresh(request));
        });
      }
    } catch (error) {
      if (mounted && request == _epoch) {
        setState(() => _error = '探索を開始できませんでした: $error');
      }
    } finally {
      if (mounted && request == _epoch) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh(int request) async {
    try {
      final result = await widget.client.snapshot();
      if (!mounted || request != _epoch) return;
      setState(() => _snapshot = result);
      if (!result.running) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } catch (error) {
      if (!mounted || request != _epoch) return;
      _cancelScan(clearResults: true);
      setState(() => _error = '探索を停止しました: $error');
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    final request = ++_epoch;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() => _busy = true);
    try {
      final result = await widget.client.stop();
      if (!mounted || request != _epoch) return;
      setState(() => _snapshot = result);
    } catch (error) {
      if (mounted && request == _epoch) {
        setState(() => _error = '停止処理を確認できませんでした: $error');
      }
    } finally {
      if (mounted && request == _epoch) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openPairing(LanDiscoveredService service) async {
    if (_busy || !CompanionPairingClient.isPrivateIpv4(service.address) ||
        service.port < 1 || service.port > 65535 || !mounted) {
      return;
    }
    _epoch++;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await widget.client.stop();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _snapshot = null);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CompanionPairingPage(
        service: service,
        discoveryClient: widget.client,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final services = _snapshot?.services ?? const <LanDiscoveredService>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Chappy Network Lab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('LAN機器発見・試作版',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              '機器が公開しているDNS-SDサービスだけを探します。'
              'すべてのWi-Fi端末を列挙する機能ではありません。',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('netlab_browser'),
              onPressed: () {
                _cancelScan(clearResults: true);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const BrowserPage(),
                ));
              },
              icon: const Icon(Icons.public),
              label: const Text('ブラウザ（公開HTTPSサイト専用）'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('netlab_diagnostic'),
              onPressed: () {
                _cancelScan(clearResults: true);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const NetworkDiagnosticPage(),
                ));
              },
              icon: const Icon(Icons.network_check),
              label: const Text('ネットワーク接続診断（手動）'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('netlab_pc_identity'),
              onPressed: () {
                _cancelScan(clearResults: true);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const PcIdentityPage(),
                ));
              },
              icon: const Icon(Icons.key_outlined),
              label: const Text('PC連携用の端末キーを準備・削除'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('netlab_device_traffic'),
              onPressed: () {
                _cancelScan(clearResults: true);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const DeviceTrafficPage(),
                ));
              },
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('このスマホの通信量を測定'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('netlab_service_type'),
              initialValue: _serviceType,
              decoration: const InputDecoration(
                labelText: '探すサービス',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: '_http._tcp.',
                  child: Text('Webサービス（HTTP）'),
                ),
                DropdownMenuItem(
                  value: '_workstation._tcp.',
                  child: Text('PC・ワークステーション'),
                ),
                DropdownMenuItem(
                  value: '_ipp._tcp.',
                  child: Text('プリンター（IPP）'),
                ),
              ],
              onChanged: _busy || _scanning
                  ? null
                  : (value) {
                      if (value != null) setState(() => _serviceType = value);
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('netlab_start'),
                    onPressed: _busy || _scanning ? null : _start,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('探索開始'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  key: const Key('netlab_stop'),
                  onPressed: _busy || !_scanning ? null : _stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              SelectableText(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            Text(
              _scanning
                  ? '探索中（残り約${_snapshot!.remainingSeconds}秒）'
                  : '探索停止中',
              key: const Key('netlab_status'),
            ),
            const SizedBox(height: 14),
            Text('発見したサービス ${services.length}件',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (services.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'まだ見つかっていません。対応サービスがない場合や'
                    'ゲストWi-Fiで端末間通信が遮断されている場合は発見できません。',
                  ),
                ),
              ),
            ...services.map(
              (service) => Card(
                child: ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(service.name),
                  subtitle: Text(
                    '${service.type}\n'
                    '${service.resolved ? service.address : 'IP未解決'}'
                    '${service.port > 0 ? ':${service.port}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: service.type == '_workstation._tcp.' &&
                          service.name.startsWith('Chappy PC ') &&
                          service.resolved &&
                          CompanionPairingClient.isPrivateIpv4(service.address) &&
                          service.port > 0
                      ? const Icon(Icons.verified_user_outlined)
                      : null,
                  onTap: service.type == '_workstation._tcp.' &&
                          service.name.startsWith('Chappy PC ') &&
                          service.resolved &&
                          CompanionPairingClient.isPrivateIpv4(service.address) &&
                          service.port > 0
                      ? () => _openPairing(service)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('netlab_remote_traffic_import'),
              onPressed: () {
                _cancelScan(clearResults: true);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const RemoteTrafficImportPage(),
                ));
              },
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('ほかの端末の通信レポートを読み込む'),
            ),
            const SizedBox(height: 20),
            const Text(
              'このスマホの集計通信量とは別に、管理PCの手動JSONも読めます。'
              'ほかの機器の通信本文・PC遠隔操作は取得しません。'
              'Android 17以降でアプリがSDK 37以上を対象とする場合は、'
              'OSのサービス選択方式が完成するまで探索を行いません。'
              '画面を閉じるかアプリが裏に回ると探索を終了します。',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
