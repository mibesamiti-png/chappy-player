import 'dart:typed_data';

import 'package:chappy_player/core/remote_traffic_report.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// The trusted Android host imports a chosen file; no network polling or JS API.
class RemoteTrafficImportPage extends StatefulWidget {
  final Future<Uint8List?> Function()? pickReport;
  const RemoteTrafficImportPage({super.key, this.pickReport});

  @override
  State<RemoteTrafficImportPage> createState() =>
      _RemoteTrafficImportPageState();
}

class _RemoteTrafficImportPageState extends State<RemoteTrafficImportPage>
    with WidgetsBindingObserver {
  RemoteTrafficReport? _report;
  String? _notice;
  bool _busy = false;
  bool _foreground = true;
  bool _promptPending = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _foreground = false;
      _clear('背景化したため結果を破棄しました');
    } else {
      _foreground = true;
    }
  }

  void _clear([String? reason]) {
    _generation++;
    if (mounted) {
      setState(() {
        _report = null;
        _busy = false;
        _notice = reason;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  Future<Uint8List?> _pickFile() async {
    final chosen = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (chosen == null || chosen.files.isEmpty) return null;
    final file = chosen.files.single;
    if (file.size > RemoteTrafficReport.maxFileBytes) {
      throw const FormatException('16KiBを超えるJSONは読み込めません');
    }
    return file.bytes;
  }

  Future<void> _import() async {
    if (_busy || _promptPending || !_foreground) return;
    _promptPending = true;
    final before = _generation;
    bool approved = false;
    try {
      approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('PCの通信レポートを読み込む'),
          content: const Text('自分が管理するWindows PCで、本人が計測を許可して'
              '生成したJSONだけを選んでください。\n\n'
              'ファイルは通信量のみで、Wi-Fiだけの値とは限りません。'
              '閲覧履歴・通信先・本文・パスワードは表示できません。'
              'ファイルは未署名のため本物のPCデータかの証明にはなりません。'
              '結果はメモリのみで保持し、画面を離れると消えます。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('キャンセル')),
            FilledButton(
              key: const Key('remote_traffic_approve'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('JSONを選ぶ')),
          ],
        ),
      ) ?? false;
    } finally {
      _promptPending = false;
    }
    if (!mounted || !_foreground || before != _generation || !approved) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _report = null;
      _notice = null;
    });
    try {
      final bytes = await (widget.pickReport?.call() ?? _pickFile());
      if (!mounted || !_foreground || generation != _generation) return;
      if (bytes == null) {
        setState(() => _notice = '選択をキャンセルしました');
      } else {
        final parsed = RemoteTrafficReport.parseBytes(bytes);
        if (mounted && _foreground && generation == _generation) {
          setState(() => _report = parsed);
        }
      }
    } on FormatException catch (error) {
      if (mounted && _foreground && generation == _generation) {
        setState(() => _notice = error.message);
      }
    } catch (_) {
      if (mounted && _foreground && generation == _generation) {
        setState(() => _notice = 'レポートを読み込めませんでした');
      }
    } finally {
      if (mounted && _foreground && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  static String _bytes(num value) {
    var amount = value.toDouble();
    const suffixes = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var index = 0;
    while (amount >= 1024 && index < suffixes.length - 1) {
      amount /= 1024;
      index++;
    }
    return amount.toStringAsFixed(index == 0 ? 0 : 1) + ' ' + suffixes[index];
  }

  Widget _metric(String name, num amount, String key) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 5),
          Text(_bytes(amount), key: Key(key),
              style: const TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('ほかの端末の通信レポート')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('NETLAB-04A / Windows PCレポート',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('PC側でStart-ChappyTrafficExport.cmdを実行し、'
              '出力されたJSONをスマホへ移して読み込みます。'
              'これはファイル経由で、Wi-Fiからの自動・リアルタイム取得ではありません。'),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('remote_traffic_import'),
            onPressed: _busy || !_foreground ? null : _import,
            icon: const Icon(Icons.file_open),
            label: const Text('ほかの端末のレポートを読み込む')),
          if (_busy) const LinearProgressIndicator(),
          if (_notice != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_notice!, key: const Key('remote_traffic_notice')),
          ),
          if (report != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _metric('合計受信', report.totalRxBytes,
                  'remote_traffic_rx')),
              Expanded(child: _metric('合計送信', report.totalTxBytes,
                  'remote_traffic_tx')),
            ]),
            Row(children: [
              Expanded(child: _metric('平均受信/秒',
                  report.avgRxBytesPerSecond, 'remote_traffic_avg_rx')),
              Expanded(child: _metric('平均送信/秒',
                  report.avgTxBytesPerSecond, 'remote_traffic_avg_tx')),
            ]),
            Text('計測時間: ' + report.seconds.toString() + '秒',
                key: const Key('remote_traffic_summary')),
            const SizedBox(height: 12),
            Text('1秒ごとの受信量（全アダプター）',
                style: Theme.of(context).textTheme.titleMedium),
            ...List.generate(report.samples.length, (index) {
              final point = report.samples[index];
              final maxRx = report.peakRxBytesPerSecond;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 45,
                      child: Text((index + 1).toString() + '秒')),
                  Expanded(child: LinearProgressIndicator(
                    value: maxRx == 0 ? 0.0 : point.rxBytes / maxRx,
                    minHeight: 8)),
                  const SizedBox(width: 8),
                  SizedBox(width: 90,
                    child: Text(_bytes(point.rxBytes),
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.end)),
                ]),
              );
            }),
            const SizedBox(height: 10),
            Text('最大受信/秒: ' + _bytes(report.peakRxBytesPerSecond) +
                 '  最大送信/秒: ' + _bytes(report.peakTxBytesPerSecond)),
            TextButton.icon(
              key: const Key('remote_traffic_clear'),
              onPressed: () => _clear('結果を破棄しました'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('読み込んだ結果を消去')),
          ],
          const SizedBox(height: 18),
          const Text('本機能はWi-Fi上のほかの端末を無断で調べません。'
              'データは端末内メモリのみで保持し、背景化や閉じる操作で消去します。'
              'ルーター/スマホなど別種の機器は専用の同意済み計測元が必要です。',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
        ],
      )),
    );
  }
}
