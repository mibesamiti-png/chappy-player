import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/data_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory dataRoot;
  late DataBackupService backup;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('chappy_data_backup_');
    dataRoot = Directory(p.join(temp.path, 'library', 'data'))
      ..createSync(recursive: true);
    backup = DataBackupService(dataRoot);
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Uint8List snapshot(String id, Map<String, dynamic> values) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'type': 'chappy-data-backup',
        'formatVersion': 1,
        'createdAt': '2026-11-04T00:00:00Z',
        'apps': [{'id': id, 'values': values}],
      })));

  test('export, inspect, restore preserve all JSON values', () async {
    final data = File(p.join(dataRoot.path, 'local.chappy.memo.json'));
    data.writeAsStringSync(jsonEncode({
      'note': 'Hello 日本語',
      'counter': 42,
      'settings': {'dark': true},
    }));
    final bytes = await backup.exportData();
    final parsed = backup.inspect(bytes);
    expect(parsed.ids, ['local.chappy.memo']);
    expect(parsed.apps['local.chappy.memo']!['note'], 'Hello 日本語');
    data.writeAsStringSync('{"note":"changed"}');
    expect(await backup.restore(bytes), 1);
    expect(jsonDecode(data.readAsStringSync())['note'], 'Hello 日本語');
  });

  test('reject path traversal and malformed snapshots before writing', () async {
    final target = File(p.join(dataRoot.path, 'local.chappy.memo.json'));
    target.writeAsStringSync('{"note":"safe"}');
    expect(() => backup.inspect(snapshot('../outside', {'note': 'attack'})),
        throwsFormatException);
    expect(() => backup.inspect(snapshot('local.chappy.memo', {'': 1})),
        throwsFormatException);
    expect(() => backup.inspect(Uint8List.fromList([0, 1, 2])),
        throwsFormatException);
    expect(target.readAsStringSync(), contains('safe'));
  });

  test('recovery reverses interrupted restore', () async {
    final current = File(p.join(dataRoot.path, 'local.chappy.memo.json'))
      ..writeAsStringSync('{"note":"original"}');
    final pending = Directory(p.join(temp.path, 'library', 'pending-data-restore'));
    final old = File(p.join(pending.path, 'old', 'local.chappy.memo.json'));
    old.parent.createSync(recursive: true);
    old.writeAsStringSync(current.readAsStringSync());
    File(p.join(pending.path, 'plan.json'))
        .writeAsStringSync(jsonEncode(['local.chappy.memo']));
    File(p.join(pending.path, 'READY')).writeAsStringSync('ready');
    current.writeAsStringSync('{"note":"partial restore"}');

    await backup.recoverInterruptedRestore();
    expect(jsonDecode(current.readAsStringSync())['note'], 'original');
    expect(pending.existsSync(), isFalse);
  });

  test('completed restore is not rolled back on restart', () async {
    final current = File(p.join(dataRoot.path, 'local.chappy.memo.json'))
      ..writeAsStringSync('{"note":"new"}');
    final pending = Directory(p.join(temp.path, 'library', 'pending-data-restore'))
      ..createSync(recursive: true);
    File(p.join(pending.path, 'COMPLETED')).writeAsStringSync('complete');
    await backup.recoverInterruptedRestore();
    expect(jsonDecode(current.readAsStringSync())['note'], 'new');
    expect(pending.existsSync(), isFalse);
  });
}
