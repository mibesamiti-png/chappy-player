import 'dart:async';

import 'package:chappy_player/core/network_diagnostic_service.dart';
import 'package:flutter/material.dart';

/// Host-only one-shot connectivity test; never a .chappy JavaScript API.
class NetworkDiagnosticPage extends StatefulWidget {
  final NetworkDiagnosticService Function()? serviceFactory;
  const NetworkDiagnosticPage({super.key, this.serviceFactory});

  @override
  State<NetworkDiagnosticPage> createState() => _NetworkDiagnosticPageState();
}

class _NetworkDiagnosticPageState extends State<NetworkDiagnosticPage>
    with WidgetsBindingObserver {
  NetworkDiagnosticService? _active;
  NetworkDiagnosticSnapshot? _result;
  String? _message;
  int _epoch = 0;
  bool _busy = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _cancel() {
    ++_epoch;
    _active?.cancel();
    _active = null;
    if (mounted) {
      setState(() {
      _busy = false;
      _result = null;
      _message = '診断を中止しました。結果は保存していません。';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
    } else {
      _foreground = false;
      _cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_epoch;
    _active?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy || !_foreground) return;
    final beforeConsent = _epoch;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('1回だけネットワーク診断'),
        content: const Text(
          '接続インターフェース数を確認した後、example.com宛に'
          'DNS問い合わせとHTTPS HEADを1回ずつ送信します。\n\n'
          '相手のサイトには接続元IPが見える場合があります。'
          'LAN全域の探索・通信監視・秘密情報や位置情報の収集はしません。'
          '結果は画面内だけに表示し、自動保存・送信しません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('今回だけ診断する')),
        ],
      ),
    );
    if (!mounted || !_foreground || beforeConsent != _epoch ||
        accepted != true) return;
    final request = ++_epoch;
    final service = widget.serviceFactory?.call() ?? NetworkDiagnosticService();
    _active = service;
    setState(() {
      _busy = true;
      _result = null;
      _message = null;
    });
    try {
      final result = await service.run();
      if (!mounted || request != _epoch) return;
      setState(() {
        _result = result;
        _message = result.stoppedAt == 'cancelled'
            ? '診断を中断しました。'
            : '結果はこの画面だけに表示します。';
      });
    } catch (_) {
      if (mounted && request == _epoch) {
        setState(() => _message = '通信診断に失敗しました。');
      }
    } finally {
      if (request == _epoch) {
        _active = null;
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('接続診断 — R7プレビュー')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('本人が押したときだけ動く接続確認',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('ネットワーク接続数 → example.comのDNS解決 → '
              'HTTPS HEAD応答の順に確認します。端末IPや機器名は表示しません。'),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('r7_diag_start'),
            onPressed: _busy || !_foreground ? null : _run,
            icon: const Icon(Icons.network_check),
            label: const Text('診断を開始（同意が必要）'),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
            TextButton(
              key: const Key('r7_diag_stop'),
              onPressed: _cancel,
              child: const Text('診断を中止')),
          ],
          if (_message != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!, key: const Key('r7_diag_status')),
          ),
          if (result != null) Card(child: Column(children: [
            ListTile(
              key: const Key('r7_diag_interfaces'),
              title: const Text('ネットワーク接続数'),
              trailing: Text('${result.interfaceCount} 件')),
            ListTile(
              key: const Key('r7_diag_dns'),
              title: const Text('example.comのDNS'),
              trailing: Text(result.dnsResolved ? '応答あり' : '失敗/未実施')),
            ListTile(
              key: const Key('r7_diag_https'),
              title: const Text('example.comのHTTPS'),
              trailing: Text(result.httpsStatus == null
                  ? '失敗/未実施' : 'HTTP ${result.httpsStatus}')),
            if (result.stoppedAt != null)
              ListTile(
                title: const Text('停止した段階'),
                subtitle: Text(result.stoppedAt!)),
          ])),
          const SizedBox(height: 16),
          const Text('DNS/HTTPSが失敗してもWi-Fiの故障とは限りません。'
              'VPN・制限ネットワークは疎通を遮断する場合があります。'
              'LANサービス発見は別画面で、必ず15秒の明示承認が必要です。',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      )),
    );
  }
}
