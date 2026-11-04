import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/log_store.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:chappy_player/core/self_check_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late PackageRepository repository;
  late LogStore logs;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('chappy_self_check_');
    repository = PackageRepository();
    await repository.init(baseDirectory: temp);
    logs = LogStore();
    await logs.init(baseDirectory: temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('reports storage, packages, local server and persisted logging', () async {
    final results = await SelfCheckService(
      repository: repository,
      logs: logs,
    ).run();
    expect(results.map((e) => e.id).toList(),
        ['storage', 'packages', 'loopback', 'diagnostics']);
    expect(results.every((e) => e.passed), isTrue,
        reason: SelfCheckService.report(results));
    expect(SelfCheckService.report(results), contains('4/4 passed'));
  });

  test('detects missing app content without crashing other checks', () async {
    await repository.install(Uint8List.fromList(
      File('sample_memo.chappy').readAsBytesSync(),
    ));
    final index = File(p.join(
      repository.currentDir('local.chappy.memo').path,
      'index.html',
    ));
    await index.delete();
    final results = await SelfCheckService(
      repository: repository,
      logs: logs,
    ).run();
    final pkg = results.singleWhere((item) => item.id == 'packages');
    expect(pkg.passed, isFalse);
    expect(pkg.detail, contains('local.chappy.memo'));
    expect(results.where((item) => item.passed).length, 3);
  });
}
