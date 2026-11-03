import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/log_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LogsPage extends StatefulWidget {
  final LogStore logs;
  final String? appId;
  const LogsPage({super.key, required this.logs, this.appId});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String filter = 'all';
  bool exporting = false;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String get _report => widget.logs.diagnosticSession == null
      ? widget.logs.report(appId: widget.appId)
      : widget.logs.diagnosticSessionReport();

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report));
    _notify('診断レポートをコピーしました。送信する前に内容を確認してください');
  }

  Future<void> _saveReport() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final text = _report;
      final timestamp = DateTime.now().toUtc().toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'chappy-diagnostic-$timestamp.txt';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '診断レポートを保存',
        fileName: fileName,
        type: FileType.any,
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (result != null) {
        _notify('診断レポートを保存しました。共有前に内容を確認してください');
      }
    } catch (error) {
      _notify('レポートの保存に失敗しました: $error');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    try {
      final note = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('再現手順を記録'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 500,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '例：メモ帳を開いて保存ボタンを押すと画面が固まる',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('追加'),
            ),
          ],
        ),
      );
      if (note == null) return;
      widget.logs.addReproductionNote(note);
      if (mounted) setState(() {});
    } catch (error) {
      _notify('メモを追加できませんでした: $error');
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = widget.logs.diagnosticSession;
    final recording = capture?.isRecording ?? false;
    final visible = widget.logs.recent.reversed.where((log) {
      if (widget.appId != null && log.appId != widget.appId) {
        return false;
      }
      if (filter == 'error') {
        return log.level.toLowerCase().contains('error') ||
            log.level.toLowerCase().contains('severe');
      }
      if (filter == 'warning') {
        return log.level.toLowerCase().contains('warn');
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('診断ログ'),
        actions: [
          IconButton(
            tooltip: '表示ログを更新',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_outlined),
          ),
          IconButton(
            tooltip: '診断レポートをコピー',
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '診断レポートをファイル保存',
            onPressed: exporting ? null : _saveReport,
            icon: const Icon(Icons.save_alt_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('不具合の再現記録',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  capture == null
                      ? '記録を開始してから不具合を再現すると、その間のログだけを取り出せます。'
                      : recording
                          ? '記録中｜対象: ${capture.appId ?? 'すべて'}｜${capture.eventCount}件'
                          : '記録終了｜${capture.eventCount}件'
                              '${capture.truncated ? '（古いログを省略）' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (!recording)
                    FilledButton.icon(
                      onPressed: () {
                        widget.logs.startDiagnosticSession(appId: widget.appId);
                        setState(() {});
                      },
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('記録開始'),
                    ),
                  if (recording)
                    FilledButton.icon(
                      onPressed: () {
                        widget.logs.stopDiagnosticSession();
                        setState(() {});
                      },
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('記録終了'),
                    ),
                  OutlinedButton.icon(
                    onPressed: recording ? _addNote : null,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('再現手順をメモ'),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text(
            'ログや手入力メモには個人情報が含まれることがあります。外部へ自動送信はしません。',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('全部')),
              ButtonSegment(value: 'error', label: Text('エラー')),
              ButtonSegment(value: 'warning', label: Text('警告')),
            ],
            selected: {filter},
            onSelectionChanged: (values) =>
                setState(() => filter = values.first),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('該当するログはありません'))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return ListTile(
                      dense: true,
                      title: Text('[${item.level}] ${item.source}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: SelectableText(
                        '${item.message}\n${item.time}  ${item.appId}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
