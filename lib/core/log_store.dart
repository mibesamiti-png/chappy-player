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

/// One user-initiated diagnostic capture. No screenshots, input text or
/// network payloads are automatically recorded by this feature.
class DiagnosticSession {
  final String startedAt;
  final String? appId;
  String? endedAt;
  bool truncated = false;
  final List<LogEntry> entries = [];

  DiagnosticSession({required this.startedAt, required this.appId});

  bool get isRecording => endedAt == null;
  int get eventCount => entries.length;

  void append(LogEntry entry) {
    if (!isRecording) return;
    if (appId != null && entry.appId != appId && entry.appId != 'player') {
      return;
    }
    if (entries.length >= 500) {
      entries.removeAt(0);
      truncated = true;
    }
    entries.add(entry);
  }
}

class LogStore {
  File? _file;
  Future<void> _pendingWrite = Future<void>.value();
  final List<LogEntry> _recent = [];
  DiagnosticSession? _capture;

  List<LogEntry> get recent => List.unmodifiable(_recent);
  DiagnosticSession? get diagnosticSession => _capture;

  /// Begin collecting logs after an explicit user tap.
  /// A new recording replaces the previous in-memory recording.
  void startDiagnosticSession({String? appId}) {
    if (_capture?.isRecording ?? false) {
      throw StateError('診断記録はすでに開始されています');
    }
    _capture = DiagnosticSession(
      startedAt: DateTime.now().toUtc().toIso8601String(),
      appId: appId,
    );
  }

  void stopDiagnosticSession() {
    final session = _capture;
    if (session == null || !session.isRecording) return;
    session.endedAt = DateTime.now().toUtc().toIso8601String();
  }

  /// Manual reproduction notes are never collected without the user's input.
  void addReproductionNote(String note) {
    final session = _capture;
    if (session == null || !session.isRecording) {
      throw StateError('診断記録を開始してください');
    }
    final text = note.trim();
    if (text.isEmpty || text.length > 500) {
      throw const FormatException('再現メモは1〜500文字にしてください');
    }
    session.append(LogEntry(
      time: DateTime.now().toUtc().toIso8601String(),
      appId: session.appId ?? 'player',
      level: 'note',
      source: 'user.reproduction',
      message: text,
    ));
  }

  String diagnosticSessionReport() {
    final session = _capture;
    if (session == null) {
      throw StateError('診断記録がありません');
    }
    final entries = session.entries.map((e) => jsonEncode(e.toJson())).join('\n');
    return 'Chappy Player diagnostic capture (v0.1.x)\n'
        'Started (UTC): ${session.startedAt}\n'
        'Ended (UTC): ${session.endedAt ?? 'recording'}\n'
        'App: ${session.appId ?? 'all'}\n'
        'Events: ${session.eventCount}\n'
        'Older events omitted: ${session.truncated}\n'
        'PRIVACY: Inspect this report before sharing. It may contain user text.\n'
        'No data is automatically uploaded.\n\n'
        '$entries\n';
  }

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
    _capture?.append(value);
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
