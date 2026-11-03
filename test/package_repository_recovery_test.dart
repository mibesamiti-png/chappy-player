import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/package_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void writeManifest(Directory dir, String version) {
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(jsonEncode({
    'formatVersion': 1,
    'id': 'local.chappy.memo',
    'name': 'Memo',
    'version': version,
    'entry': 'index.html',
    'permissions': [],
  }));
  File(p.join(dir.path, 'index.html')).writeAsStringSync('<h1>Memo</h1>');
}

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('chappy_recovery_');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('recover interrupted install and keep saved data', () async {
    final appRoot = Directory(p.join(
      temp.path, 'chappy_library', 'apps', 'local.chappy.memo',
    ));
    writeManifest(Directory(p.join(appRoot.path, 'previous')), '0.1.0');
    final data = File(p.join(temp.path, 'chappy_library', 'data',
        'local.chappy.memo.json'));
    data.parent.createSync(recursive: true);
    data.writeAsStringSync('{"notes":"my saved work"}');

    final repo = PackageRepository();
    await repo.init(baseDirectory: temp);
    expect(repo.apps.single.version, '0.1.0');
    expect(repo.currentDir('local.chappy.memo').existsSync(), isTrue);
    expect(data.readAsStringSync(), contains('my saved work'));
  });

  test('recover interruption at the start of rollback', () async {
    final appRoot = Directory(p.join(
      temp.path, 'chappy_library', 'apps', 'local.chappy.memo',
    ));
    writeManifest(Directory(p.join(appRoot.path, 'rollback_tmp')), '0.1.1');
    writeManifest(Directory(p.join(appRoot.path, 'previous')), '0.1.0');

    final repo = PackageRepository();
    await repo.init(baseDirectory: temp);
    expect(repo.apps.single.version, '0.1.1');
    expect(repo.currentDir('local.chappy.memo').existsSync(), isTrue);
    expect(repo.previousDir('local.chappy.memo').existsSync(), isTrue);
    expect(Directory(p.join(appRoot.path, 'rollback_tmp')).existsSync(), isFalse);
  });

  test('recover interruption after moving previous to current', () async {
    final appRoot = Directory(p.join(
      temp.path, 'chappy_library', 'apps', 'local.chappy.memo',
    ));
    writeManifest(Directory(p.join(appRoot.path, 'current')), '0.1.0');
    writeManifest(Directory(p.join(appRoot.path, 'rollback_tmp')), '0.1.1');

    final repo = PackageRepository();
    await repo.init(baseDirectory: temp);
    expect(repo.apps.single.version, '0.1.0');
    expect(repo.previousDir('local.chappy.memo').existsSync(), isTrue);
    expect(Directory(p.join(appRoot.path, 'rollback_tmp')).existsSync(), isFalse);
  });

  test('rebuild registry from installed package manifest', () async {
    final appRoot = Directory(p.join(
      temp.path, 'chappy_library', 'apps', 'local.chappy.memo',
    ));
    writeManifest(Directory(p.join(appRoot.path, 'current')), '0.1.1');
    writeManifest(Directory(p.join(appRoot.path, 'previous')), '0.1.0');
    final registry = File(p.join(temp.path, 'chappy_library', 'library.json'));
    registry.writeAsStringSync(jsonEncode([{
      'id': 'local.chappy.memo',
      'name': 'Memo',
      'version': '0.1.0',
      'entry': 'index.html',
      'permissions': [],
    }]));

    final repo = PackageRepository();
    await repo.init(baseDirectory: temp);
    expect(repo.apps.single.version, '0.1.1');
    final decoded = jsonDecode(registry.readAsStringSync()) as List<dynamic>;
    expect((decoded.single as Map<String, dynamic>)['version'], '0.1.1');
  });

  test('package preview does not install anything', () async {
    final repo = PackageRepository();
    await repo.init(baseDirectory: temp);
    final bytes = Uint8List.fromList(File('sample_memo.chappy').readAsBytesSync());
    final info = repo.inspect(bytes);
    expect(info.id, 'local.chappy.memo');
    expect(info.version, '0.1.0');
    expect(repo.apps, isEmpty);
  });
}