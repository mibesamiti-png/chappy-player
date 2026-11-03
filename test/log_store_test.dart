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
}