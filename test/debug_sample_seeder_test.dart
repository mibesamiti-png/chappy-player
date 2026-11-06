import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/debug_sample_seeder.dart';
import 'package:chappy_player/core/package_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class MemoryDebugBundle extends CachingAssetBundle {
  final Map<String, Uint8List> data;
  MemoryDebugBundle(this.data);

  @override
  Future<ByteData> load(String key) async {
    final bytes = data[key];
    if (bytes == null) throw StateError('Missing test asset: $key');
    return ByteData.sublistView(bytes);
  }
}

MemoryDebugBundle bundleFor(
  Uint8List bytes, {
  String hash = '',
  String version = 'v1',
  String asset = 'debug_sample_assets/memo.chappy',
  String id = 'local.chappy.memo',
}) {
  final doc = jsonEncode(<String, Object>{
    'schemaVersion': 1,
    'seedVersion': version,
    'entries': <Map<String, Object>>[
      <String, Object>{
        'id': id,
        'asset': asset,
        'sizeBytes': bytes.length,
        'sha256': hash.isEmpty ? sha256.convert(bytes).toString() : hash,
      },
    ],
  });
  return MemoryDebugBundle(<String, Uint8List>{
    DebugSampleSeeder.manifestAsset: Uint8List.fromList(utf8.encode(doc)),
    asset: bytes,
  });
}

void main() {
  late Directory tmp;
  late Uint8List original;
  late Uint8List updated;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chappy_debug_seeds_');
    original = Uint8List.fromList(File('sample_memo.chappy').readAsBytesSync());
    updated = Uint8List.fromList(
      File('sample_memo_update.chappy').readAsBytesSync(),
    );
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('seed adds offline mini-app once and does not resurrect deleted apps',
      () async {
    final repo = PackageRepository();
    await repo.init(baseDirectory: tmp);
    final seeder = DebugSampleSeeder(bundle: bundleFor(original));
    final result = await seeder.seed(repo);
    expect(result.installed, 1);
    expect(result.skipped, 0);
    expect(result.alreadySeeded, isFalse);
    expect(repo.apps.single.id, 'local.chappy.memo');
    final marker = File(p.join(repo.root.path, 'debug_samples_v1.json'));
    expect(await marker.exists(), isTrue);

    // Removal is the user's choice, never undone at every app launch.
    await repo.remove('local.chappy.memo', deleteData: false);
    expect(repo.apps, isEmpty);
    final repeat = await seeder.seed(repo);
    expect(repeat.alreadySeeded, isTrue);
    expect(repo.apps, isEmpty);
  });

  test('existing user version and notes win over debug bundled package',
      () async {
    final repo = PackageRepository();
    await repo.init(baseDirectory: tmp);
    expect((await repo.install(updated)).version, '0.1.1');
    final notes = File(p.join(
      repo.dataRoot.path, 'local.chappy.memo.json',
    ));
    notes.writeAsStringSync('{"notes":"KEEP MY DATA"}');

    final result = await DebugSampleSeeder(
      bundle: bundleFor(original),
    ).seed(repo);
    expect(result.installed, 0);
    expect(result.skipped, 1);
    expect(repo.apps.single.version, '0.1.1');
    expect(await repo.canRollback(repo.apps.single.id), isFalse);
    expect(notes.readAsStringSync(), contains('KEEP MY DATA'));
  });

  test('checksum mismatch cannot install a bundled mini-app or mark complete',
      () async {
    final repo = PackageRepository();
    await repo.init(baseDirectory: tmp);
    final seeder = DebugSampleSeeder(
      bundle: bundleFor(original, hash: List.filled(64, '0').join()),
    );
    await expectLater(seeder.seed(repo), throwsFormatException);
    expect(repo.apps, isEmpty);
    expect(
      File(p.join(repo.root.path, 'debug_samples_v1.json')).existsSync(),
      isFalse,
    );
    final repaired = await DebugSampleSeeder(
      bundle: bundleFor(original),
    ).seed(repo);
    expect(repaired.installed, 1);
    expect(repo.apps, hasLength(1));
  });

  test('unsafe asset and malformed seed version cannot reach installer',
      () async {
    final repo = PackageRepository();
    await repo.init(baseDirectory: tmp);
    await expectLater(
      DebugSampleSeeder(
        bundle: bundleFor(
          original, asset: 'debug_sample_assets/../private.chappy',
        ),
      ).seed(repo),
      throwsFormatException,
    );
    await expectLater(
      DebugSampleSeeder(
        bundle: bundleFor(original, version: '../v1'),
      ).seed(repo),
      throwsFormatException,
    );
    expect(repo.apps, isEmpty);
  });
}
