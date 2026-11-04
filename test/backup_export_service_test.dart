import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/backup_export_service.dart';
import 'package:chappy_player/core/data_backup_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Uint8List backupBytes;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chappy_verified_export_');
    final data = Directory(p.join(temp.path, 'data'));
    await data.create();
    await File(p.join(data.path, 'local.chappy.memo.json'))
        .writeAsString(jsonEncode({'notes': 'てすと', 'saved': true}));
    backupBytes = await DataBackupService(data).exportData();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('exports meaningful backup and validates source before invoking Android',
      () async {
    var invoked = false;
    final expected = sha256.convert(backupBytes).toString();
    final service = BackupExportService(
      tempDirectory: () async => temp,
      nativeWriter: (args) async {
        invoked = true;
        final source = File(args['path'] as String);
        expect(await source.readAsBytes(), backupBytes);
        expect(args['sizeBytes'], backupBytes.length);
        expect(args['sha256'], expected);
        expect(DataBackupService.inspectBackup(await source.readAsBytes())
            .apps['local.chappy.memo']!['notes'], 'てすと');
        return {
          'status': 'saved',
          'sizeBytes': backupBytes.length,
          'sha256': expected,
        };
      },
    );
    final receipt = await service.export(backupBytes,
        fileName: 'chappy-data-2026-11-04.chappybackup');
    expect(invoked, isTrue);
    expect(receipt!.sizeBytes, greaterThan(0));
    expect(receipt.sha256Hex, expected);
    expect(Directory(p.join(temp.path, 'chappy_backup_export'))
        .listSync(), isEmpty);
  });

  test('rejects 0-byte file without showing destination picker', () async {
    var invoked = false;
    final service = BackupExportService(
      tempDirectory: () async => temp,
      nativeWriter: (args) async {
        invoked = true;
        return null;
      },
    );
    await expectLater(
      service.export(Uint8List(0),
          fileName: 'chappy-data-2026-11-04.chappybackup'),
      throwsFormatException,
    );
    expect(invoked, isFalse);
  });

  test('never reports success for 0 bytes returned by Android', () async {
    final service = BackupExportService(
      tempDirectory: () async => temp,
      nativeWriter: (args) async => {
        'status': 'saved',
        'sizeBytes': 0,
        'sha256': args['sha256'],
      },
    );
    await expectLater(
      service.export(backupBytes,
          fileName: 'chappy-data-2026-11-04.chappybackup'),
      throwsFormatException,
    );
  });

  test('rejects incorrect SHA and cleans temporary source', () async {
    final service = BackupExportService(
      tempDirectory: () async => temp,
      nativeWriter: (args) async => {
        'status': 'saved',
        'sizeBytes': args['sizeBytes'],
        'sha256': List.filled(64, '0').join(),
      },
    );
    await expectLater(
      service.export(backupBytes,
          fileName: 'chappy-data-2026-11-04.chappybackup'),
      throwsFormatException,
    );
    expect(Directory(p.join(temp.path, 'chappy_backup_export'))
        .listSync(), isEmpty);
  });

  test('cancelled document picker does not claim success', () async {
    final service = BackupExportService(
      tempDirectory: () async => temp,
      nativeWriter: (args) async => {'status': 'cancelled'},
    );
    final receipt = await service.export(backupBytes,
        fileName: 'chappy-data-2026-11-04.chappybackup');
    expect(receipt, isNull);
  });
}
