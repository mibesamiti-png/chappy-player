import 'dart:io';
import 'dart:typed_data';

import 'package:chappy_player/core/data_backup_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef NativeBackupWriter = Future<Map<dynamic, dynamic>?> Function(
    Map<String, dynamic> args);

class BackupExportReceipt {
  final int sizeBytes;
  final String sha256Hex;
  const BackupExportReceipt(this.sizeBytes, this.sha256Hex);
}

/// A verified backup export using Android Storage Access Framework.
/// Android verifies a destination read-back before reporting success.
class BackupExportService {
  static const channel = MethodChannel('dev.chappy.player/backup_export');

  final NativeBackupWriter _nativeWriter;
  final Future<Directory> Function() _tempDirectory;

  BackupExportService({
    NativeBackupWriter? nativeWriter,
    Future<Directory> Function()? tempDirectory,
  })  : _nativeWriter = nativeWriter ??
            ((args) => channel.invokeMapMethod<dynamic, dynamic>(
                  'exportVerifiedBackup', args)),
        _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  Future<BackupExportReceipt?> export(
    Uint8List backupBytes, {
    required String fileName,
  }) async {
    // Reject a corrupt backup before Android creates a destination file.
    final snapshot = DataBackupService.inspectBackup(backupBytes);
    if (snapshot.appCount == 0) {
      throw const FormatException(
        '保存データが見つかりません。0件のバックアップは出力しません。',
      );
    }
    if (!RegExp(r'^chappy-data-\d{4}-\d{2}-\d{2}\.chappybackup$')
        .hasMatch(fileName)) {
      throw const FormatException('不正なバックアップファイル名です');
    }

    final root = await _tempDirectory();
    final stage = await Directory(
      p.join(root.path, 'chappy_backup_export'),
    ).create(recursive: true);
    final staging = File(p.join(
      stage.path,
      'backup_${DateTime.now().microsecondsSinceEpoch}.chappybackup',
    ));
    try {
      await staging.writeAsBytes(backupBytes, flush: true);
      final expectedSize = backupBytes.length;
      if (await staging.length() != expectedSize) {
        throw const FileSystemException('バックアップの一時保存サイズが一致しません');
      }
      final expectedHash = sha256.convert(backupBytes).toString();
      final stagingHash = (await sha256.bind(staging.openRead()).first).toString();
      if (expectedHash != stagingHash) {
        throw const FormatException('一時バックアップのSHA-256検証に失敗しました');
      }

      final result = await _nativeWriter({
        'path': staging.absolute.path,
        'fileName': fileName,
        'sizeBytes': expectedSize,
        'sha256': expectedHash,
      });
      if (result == null || result['status'] == 'cancelled') return null;
      if (result['status'] != 'saved' ||
          result['sizeBytes'] != expectedSize ||
          result['sha256'] != expectedHash) {
        throw const FormatException(
          '外部保存先の読み戻し検証に失敗したため、保存成功とは判定しません。',
        );
      }
      return BackupExportReceipt(expectedSize, expectedHash);
    } on MissingPluginException {
      throw const FormatException(
        'このバージョンは検証付きバックアップ保存に未対応です。',
      );
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }
}
