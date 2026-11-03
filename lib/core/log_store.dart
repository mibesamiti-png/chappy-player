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
  bool recoveredAfterInterruption = false;
  final List<LogEntry> entries = [];

  DiagnosticSession({required this.startedAt, required this.appId});

  bool get isRecording => endedAt == null;
  int get eventCount => entries.length;

  void append(LogEntry entry) {
    if (!isRecording) { return; }
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
  File? _captureStateFile;
  Future<void> _pendingWrite = Future<void>.value();
  final List<LogEntry> _recent = [];
  DiagnosticSession? _capture;

  List<LogEntry> get recent => List.unmodifiable(_recent);
  DiagnosticSession? get diagnosticSession => _capture;

  /// Begin collecting logs after an explicit user tap.
  /// A new recording replaces the previous in-memory recording.
  Future<void> startDiagnosticSession({String? appId}) async {
    if (_capture?.isRecording ?? false) {
      throw StateError('診断記録はすでに開始されています');
    }
    await _pendingWrite;
    _capture = DiagnosticSession(
      startedAt: DateTime.now().toUtc().toIso8601String(),
      appId: appId,
    );
    await _saveCaptureState();
  }

  Future<void> stopDiagnosticSession() async {
    final session = _capture;
    if (session == null || !session.isRecording) { return; }
    await _pendingWrite;
    session.endedAt = DateTime.now().toUtc().toIso8601String();
    await _saveCaptureState();
  }

  /// Manual reproduction notes are never collected without the user's input.
  Future<void> addReproductionNote(String note) async {
    final session = _capture;
    if (session == null || !session.isRecording) {
      throw StateError('診断記録を開始してください');
    }
    final text = note.trim();
    if (text.isEmpty || text.length > 500) {
      throw const FormatException('再現メモは1〜500文字にしてください');
    }
    await add(session.appId ?? 'player', 'note', 'user.reproduction', text);
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
        'Recovered after interruption: ${session.recoveredAfterInterruption}\n'
        'PRIVACY: Inspect this report before sharing. It may contain user text.\n'
        'No data is automatically uploaded.\n\n'
        '$entries\n';
  }

  Future<void> init({Directory? baseDirectory}) async {
    final docs = baseDirectory ?? await getApplicationDocumentsDirectory();
    _file = File(p.join(docs.path, 'chappy_diagnostics.jsonl'));
    _captureStateFile = File(p.join(docs.path, 'chappy_capture_state.json'));
    await _loadCaptureState();

    // Reconstruct an interrupted recording from durable diagnostic logs.
    // Both files are bounded; reading corrupt lines never prevents startup.
    final candidates = [
      File('${_file!.path}.old'),
      _file!,
    ];
    for (final file in candidates) {
      if (!await file.exists()) { continue; }
      if (await file.length() > 1024 * 1024) {
        if (file.path == _file!.path) { await _rotate(); }
        continue;
      }
      final lines = await file.readAsLines();
      for (final line in lines) {
        try {
          final entry = LogEntry.fromJson(
              jsonDecode(line) as Map<String, dynamic>);
          _recent.add(entry);
          final capture = _capture;
          if (capture != null &&
              entry.time.compareTo(capture.startedAt) >= 0 &&
              (capture.endedAt == null ||
                  entry.time.compareTo(capture.endedAt!) <= 0)) {
            // Recovery also adds entries from the completed recording.
            final wasEnded = capture.endedAt;
            capture.endedAt = null;
            capture.append(entry);
            capture.endedAt = wasEnded;
          }
        } catch (_) {
          // A partially written log line must never prevent startup.
        }
      }
    }
    if (_recent.length > 200) {
      _recent.removeRange(0, _recent.length - 200);
    }
  }

  Future<void> _loadCaptureState() async {
    final file = _captureStateFile!;
    if (!await file.exists()) { return; }
    try {
      if (await file.length() > 8192) {
        throw const FormatException('Capture state too large');
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic> ||
          value['formatVersion'] != 1 ||
          value['startedAt'] is! String ||
          (value['appId'] != null && value['appId'] is! String) ||
          (value['endedAt'] != null && value['endedAt'] is! String)) {
        throw const FormatException('Invalid capture state');
      }
      final session = DiagnosticSession(
        startedAt: value['startedAt'] as String,
        appId: value['appId'] as String?,
      );
      session.endedAt = value['endedAt'] as String?;
      if (session.endedAt == null) {
        // A prior process died before the user could press Stop.
        session.recoveredAfterInterruption = true;
        session.endedAt = DateTime.now().toUtc().toIso8601String();
      }
      _capture = session;
    } catch (_) {
      _recent.add(LogEntry(
        time: DateTime.now().toUtc().toIso8601String(),
        appId: 'player',
        level: 'warning',
        source: 'diagnostics',
        message: '保存された診断記録の状態を読み取れませんでした',
      ));
    }
  }

  Future<void> _saveCaptureState() async {
    final file = _captureStateFile;
    final capture = _capture;
    if (file == null || capture == null) { return; }
    await file.parent.create(recursive: true);
    final next = File('${file.path}.tmp');
    await next.writeAsString(jsonEncode({
      'formatVersion': 1,
      'startedAt': capture.startedAt,
      'appId': capture.appId,
      'endedAt': capture.endedAt,
    }), flush: true);
    await next.rename(file.path);
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
