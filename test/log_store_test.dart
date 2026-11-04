import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/log_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('chappy_logs_');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('concurrent diagnostics produce valid JSON lines', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await Future.wait(List.generate(100, (index) =>
        logs.add('local.chappy.memo', 'error', 'test', 'Error $index')));
    final file = File(p.join(temp.path, 'chappy_diagnostics.jsonl'));
    final lines = file.readAsLinesSync();
    expect(lines.length, 100);
    for (final line in lines) {
      final parsed = jsonDecode(line) as Map<String, dynamic>;
      expect(parsed['appId'], 'local.chappy.memo');
      expect(parsed['level'], 'error');
    }
    expect(logs.recent.length, 100);
  });

  test('reports only selected app and persists recent log', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await logs.add('app.one', 'info', 'test', 'first');
    await logs.add('app.two', 'warning', 'test', 'second');
    final report = logs.report(appId: 'app.one');
    expect(report, contains('first'));
    expect(report, isNot(contains('second')));

    final reopened = LogStore();
    await reopened.init(baseDirectory: temp);
    expect(reopened.recent.length, 2);
  });
  test('recording is opt-in and filters to target app', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await logs.add('app.one', 'info', 'test', 'before recording');
    await logs.startDiagnosticSession(appId: 'app.one');
    await logs.add('app.one', 'error', 'js', 'target error');
    await logs.add('app.two', 'error', 'js', 'other app secret');
    await logs.add('player', 'warning', 'flutter', 'host warning');
    await logs.addReproductionNote('Press save, then the app freezes');
    await logs.stopDiagnosticSession();
    await logs.add('app.one', 'error', 'js', 'after recording');
    final report = logs.diagnosticSessionReport();
    expect(report, contains('target error'));
    expect(report, contains('host warning'));
    expect(report, contains('Press save'));
    expect(report, isNot(contains('before recording')));
    expect(report, isNot(contains('other app secret')));
    expect(report, isNot(contains('after recording')));
    expect(logs.diagnosticSession!.eventCount, 3);
  });

  test('recording limits entries and preserves truncation flag', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await logs.startDiagnosticSession();
    for (var i = 0; i < 520; i++) {
      await logs.add('app.test', 'info', 'test', 'entry $i');
    }
    await logs.stopDiagnosticSession();
    final capture = logs.diagnosticSession!;
    expect(capture.eventCount, 500);
    expect(capture.truncated, isTrue);
    expect(logs.diagnosticSessionReport(), contains('Older events omitted: true'));
    expect(logs.diagnosticSessionReport(), contains('entry 519'));
    expect(logs.diagnosticSessionReport(), isNot(contains('entry 0"')));
  });

  test('recovers unfinished recording from persistent diagnostic logs', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await logs.startDiagnosticSession(appId: 'app.one');
    await logs.add('app.one', 'error', 'javascript', 'crash before stop');
    await logs.addReproductionNote('tap save causes crash');
    await logs.add('app.two', 'error', 'javascript', 'other app');

    // A new store is equivalent to a process restart without pressing Stop.
    final reopened = LogStore();
    await reopened.init(baseDirectory: temp);
    final recovered = reopened.diagnosticSession!;
    expect(recovered.isRecording, isFalse);
    expect(recovered.recoveredAfterInterruption, isTrue);
    final report = reopened.diagnosticSessionReport();
    expect(report, contains('crash before stop'));
    expect(report, contains('tap save causes crash'));
    expect(report, isNot(contains('other app')));
    expect(report, contains('Recovered after interruption: true'));
  });

  test('completed capture is preserved without crash flag', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await logs.startDiagnosticSession();
    await logs.add('app.test', 'error', 'test', 'recorded before stop');
    await logs.stopDiagnosticSession();

    final reopened = LogStore();
    await reopened.init(baseDirectory: temp);
    expect(reopened.diagnosticSession!.isRecording, isFalse);
    expect(reopened.diagnosticSession!.recoveredAfterInterruption, isFalse);
    expect(reopened.diagnosticSessionReport(), contains('recorded before stop'));
  });

  test('reproduction notes require active recording', () async {
    final logs = LogStore();
    await logs.init(baseDirectory: temp);
    await expectLater(logs.addReproductionNote('x'), throwsStateError);
    await logs.startDiagnosticSession();
    await expectLater(logs.startDiagnosticSession(), throwsStateError);
    await expectLater(logs.addReproductionNote(''), throwsFormatException);
    await logs.stopDiagnosticSession();
    await expectLater(logs.addReproductionNote('too late'), throwsStateError);
  });

}