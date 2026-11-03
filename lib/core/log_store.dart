import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LogEntry {
  final String time;
  final String appId;
  final String level;
  final String source;
  final String message;

  const LogEntry({
    required this.time,
    required this.appId,
    required this.level,
    required this.source,
    required this.message,
  });

  Map<String, String> toJson() => {
    'time': time,
    'appId': appId,
    'level': level,
    'source': source,
    'message': message,
  };

  factory LogEntry.fromJson(Map<String, dynamic> value) => LogEntry(
    time: value['time'] as String? ?? '',
    appId: value['appId'] as String? ?? '',
    level: value['level'] as String? ?? '',
    source: value['source'] as String? ?? '',
    message: value['message'] as String? ?? '',
  );
}

class LogStore {
  File? _file;
  Future<void> _pendingWrite = Future<void>.value();
  final List<LogEntry> _recent = [];

  List<LogEntry> get recent => List.unmodifiable(_recent);

  Future<void> init({Directory? baseDirectory}) async {
    final docs = baseDirectory ?? await getApplicationDocumentsDirectory();
    _file = File(p.join(docs.path, 'chappy_diagnostics.jsonl'));
    if (!(await _file!.exists())) return;
    final length = await _file!.length();
    if (length > 1024 * 1024) {
      await _rotate();
      return;
    }
    final lines = await _file!.readAsLines();
    for (final line in lines.skip(lines.length > 200 ? lines.length - 200 : 0)) {
      try {
        _recent.add(LogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        // A partially written log line must never prevent startup.
      }
    }
  }

  Future<void> add(String appId, String level, String source, String message) {
    final value = LogEntry(
      time: DateTime.now().toUtc().toIso8601String(),
      appId: appId,
      level: level,
      source: source,
      message: message.length > 2000 ? '${message.substring(0, 2000)}…' : message,
    );
    _recent.add(value);
    if (_recent.length > 200) _recent.removeAt(0);
    // Avoid interleaved append and rotation when many errors arrive together.
    final write = _pendingWrite.then((_) async {
      try {
        final file = _file;
        if (file == null) return;
        if (await file.exists() && await file.length() > 1024 * 1024) {
          await _rotate();
        }
        await file.writeAsString('${jsonEncode(value.toJson())}\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // Diagnostics failure must not crash the mini app.
      }
    });
    _pendingWrite = write;
    return write;
  }

  Future<void> _rotate() async {
    final file = _file;
    if (file == null || !(await file.exists())) return;
    final backup = File('${file.path}.old');
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
  }

  String report({String? appId}) {
    final entries = _recent.where((e) => appId == null || e.appId == appId);
    final lines = entries.map((e) => jsonEncode(e.toJson())).join('\n');
    return 'Chappy Player v0.1.0 diagnostic report\n'
        'Generated: ${DateTime.now().toUtc().toIso8601String()}\n'
        'App: ${appId ?? 'all'}\n'
        'NOTICE: Review contents before sharing. Logs can contain personal data.\n\n'
        '$lines\n';
  }
}
