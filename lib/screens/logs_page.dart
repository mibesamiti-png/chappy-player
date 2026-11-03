import 'package:chappy_player/core/log_store.dart';
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

  @override
  Widget build(BuildContext context) {
    final visible = widget.logs.recent.reversed.where((log) {
      if (widget.appId != null && log.appId != widget.appId) return false;
      if (filter == 'error') {
        return log.level.toLowerCase().contains('error') ||
            log.level.toLowerCase().contains('severe');
      }
      if (filter == 'warning') return log.level.toLowerCase().contains('warn');
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('診断ログ'), actions: [
        IconButton(
          tooltip: '診断レポートをコピー',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.logs.report(appId: widget.appId)));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('診断レポートをコピーしました。共有前に内容を確認してください')),
              );
            }
          },
          icon: const Icon(Icons.copy_all_outlined),
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('全部')),
              ButtonSegment(value: 'error', label: Text('エラー')),
              ButtonSegment(value: 'warning', label: Text('警告')),
            ],
            selected: {filter},
            onSelectionChanged: (values) => setState(() => filter = values.first),
          ),
        ),
        Expanded(child: visible.isEmpty
            ? const Center(child: Text('該当するログはありません'))
            : ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final item = visible[index];
                  return ListTile(
                    dense: true,
                    title: Text('[${item.level}] ${item.source}', style: const TextStyle(fontSize: 13)),
                    subtitle: SelectableText('${item.message}\n${item.time}  ${item.appId}',
                        style: const TextStyle(fontSize: 12)),
                  );
                },
              )),
      ]),
    );
  }
}
