// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:typed_data';

import 'package:chappy_player/core/pcap_inspector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Trusted host-only offline analysis of a user-selected authorized PCAP.
/// No live traffic capture, other-device credential access or mini-app API.
class TrafficInspectionPage extends StatefulWidget {
  final Future<Uint8List?> Function()? pickCapture;

  const TrafficInspectionPage({super.key, this.pickCapture});

  @override
  State<TrafficInspectionPage> createState() => _TrafficInspectionPageState();
}

class _TrafficInspectionPageState extends State<TrafficInspectionPage>
    with WidgetsBindingObserver {
  PcapInspection? _inspection;
  bool _foreground = true;
  bool _loading = false;
  bool _showPlaintext = false;
  bool _ownerApproved = false;
  int _generation = 0;
  String? _message;
  final _focusIp = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear([String? reason]) {
    _generation++;
    _inspection = null;
    _showPlaintext = false;
    _ownerApproved = false;
    _focusIp.clear();
    if (mounted) setState(() {
      _loading = false;
      _message = reason;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _foreground = false;
      _clear('背景化したので解析結果を破棄しました');
    } else {
      _foreground = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _inspection = null;
    _focusIp.dispose();
    super.dispose();
  }

  Future<Uint8List?> _pick() async {
    final chosen = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pcap', 'cap'],
      allowMultiple: false,
      withData: true,
    );
    if (chosen == null || chosen.files.isEmpty) return null;
    final file = chosen.files.single;
    if (file.size > PcapInspector.maxFileBytes) {
      throw const FormatException('classic PCAPファイルは2MiB以下にしてください');
    }
    if (file.bytes == null || file.bytes!.length != file.size) {
      throw const FormatException('ファイルを安全に読み込めませんでした');
    }
    return file.bytes;
  }

  Future<void> _import() async {
    if (_loading || !_foreground || !_ownerApproved ||
        ModalRoute.of(context)?.isCurrent != true) return;
    final before = _generation;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('許可を得た通信データを解析'),
        content: const Text(
          '自分で取得したデータ、または対象端末の所有者から解析許可を得た'
          'classic PCAPファイルだけを選んでください。\n\n'
          '通信先IP/ポート、DNS名、TLSのSNI候補、平文HTTPの'
          'メソッド/パスをこのスマホ内で解析します。'
          '本文表示を有効にすると、平文HTTPのtext/plainまたはJSON本文から'
          '短いプレビューを表示します。秘密情報らしい文言は非表示にしますが、'
          '完全な個人情報検出は保証できません。\n\n'
          'HTTPS/QUICの暗号化本文は読めません。'
          '通信のリアルタイム傍受や他端末への侵入はしません。'
          'ファイルや結果をネットワーク送信・永続保存しません。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('キャンセル')),
          FilledButton(
            key: const Key('traffic_inspect_approve'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('PCAPを選択'),
          ),
        ],
      ),
    );
    if (!mounted || !_foreground || !_ownerApproved ||
        before != _generation || accepted != true) return;

    final generation = ++_generation;
    setState(() {
      _loading = true;
      _inspection = null;
      _message = null;
    });
    try {
      final bytes = await (widget.pickCapture?.call() ?? _pick());
      if (!mounted || !_foreground || generation != _generation) return;
      if (bytes == null) {
        setState(() => _message = 'ファイル選択をキャンセルしました');
      } else {
        final result = PcapInspector.parseBytes(
          bytes, includePlaintextBody: _showPlaintext,
        );
        if (mounted && _foreground && generation == _generation) {
          setState(() => _inspection = result);
        }
      }
    } on FormatException catch (error) {
      if (mounted && _foreground && generation == _generation) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted && _foreground && generation == _generation) {
        setState(() => _message = 'PCAPファイルを解析できませんでした');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _inspection;
    final focus = _focusIp.text.trim();
    final all = info?.observations ?? const <PcapObservation>[];
    final rows = focus.isEmpty
        ? all
        : all.where((item) => item.sourceIp == focus).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('通信先・内容の解析')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('NETLAB-06A｜通信キャプチャ解析（オフライン）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          const SizedBox(height: 8),
          const Text(
            '手元の許可済みPCAPから、どのIP・ポートへ接続しようとしたか、'
            'DNS問い合わせ・TLSのホスト候補・平文HTTPの情報を分析します。'
            'BUFFALOルーターから自動的に通信を取得する機能ではありません。',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const Key('traffic_inspect_owner'),
            value: _ownerApproved,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _loading ? null : (v) =>
                setState(() => _ownerApproved = v == true),
            title: const Text('自分が管理・解析許可を得た通信データのみ使用する'),
          ),
          CheckboxListTile(
            key: const Key('traffic_inspect_plaintext'),
            value: _showPlaintext,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _loading ? null : (v) =>
                setState(() => _showPlaintext = v == true),
            title: const Text('平文HTTPの短い本文も表示（オプション・注意）'),
            subtitle: const Text('機微情報の混入に注意。HTTPSの本文は読めません'),
          ),
          FilledButton.icon(
            key: const Key('traffic_inspect_import'),
            onPressed: _loading || !_ownerApproved || !_foreground
                ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('PCAPファイルを解析'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('traffic_inspect_clear'),
            onPressed: () => _clear('表示と同意状態を破棄しました'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('結果を消去'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, key: const Key('traffic_inspect_status')),
          ],
          if (info != null) ...[
            const SizedBox(height: 16),
            Text('解析 ${info.packetCount}パケット／表示 ${rows.length}件',
                key: const Key('traffic_inspect_count'),
                style: Theme.of(context).textTheme.titleMedium),
            if (info.truncated)
              const Text('表示は最初の160件までです。全パケットを一覧表示していません。'),
            const SizedBox(height: 10),
            TextField(
              key: const Key('traffic_inspect_focus'),
              controller: _focusIp,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '送信元IPv4で絞り込み（任意）',
                hintText: '192.168.11.10',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            for (final item in rows)
              Card(child: ListTile(
                title: Text(
                  '${item.sourceIp} → ${item.destinationIp}:${item.destinationPort}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.protocol}／${item.description}'),
                    if (item.hostHint != null)
                      Text('ドメイン候補・問い合わせ: ${item.hostHint}'),
                    if (item.plaintextPreview != null)
                      SelectableText(
                        '平文HTTP本文（冒頭・未完全）: ${item.plaintextPreview}',
                        key: const Key('traffic_inspect_body'),
                      ),
                    if (item.encrypted)
                      const Text('暗号化：通信本文は表示できません'),
                  ],
                ),
                isThreeLine: true,
              )),
          ],
          const SizedBox(height: 14),
          const Text(
            '対応：classic PCAP 2.4、Ethernet/Raw IPv4、TCP/UDP。'
            '最大2MiB/2500パケット、IPv6とPCAPNGは未対応。'
            'TCPストリームの組立は行わず、一部のDNS/SNI/HTTP情報は'
            'パケット分割・ECH・DoH・VPNなどで読み取れません。'
            'DNS問い合わせと実際の訪問先は同一とは限りません。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      )),
    );
  }
}
