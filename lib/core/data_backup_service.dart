import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Portable JSON backup of mini-app **user data only**.
/// It contains no executable app packages, but stored data may include secrets.
/// Treat exported backups as sensitive, unencrypted files.
class BackupSnapshot {
  final Map<String, Map<String, dynamic>> apps;
  final String createdAt;
  const BackupSnapshot(this.apps, this.createdAt);
  int get appCount => apps.length;
  List<String> get ids => apps.keys.toList()..sort();
}

class DataBackupService {
  final Directory dataRoot;
  DataBackupService(this.dataRoot);

  static const maxBytes = 12 * 1024 * 1024;
  static const maxAppBytes = 1024 * 1024;
  static const maxApps = 100;
  static final _idPattern = RegExp(
    r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$',
  );

  Directory get _pending => Directory(p.join(dataRoot.parent.path, 'pending-data-restore'));

  static void _checkId(String id) {
    if (id.length > 100 || !_idPattern.hasMatch(id)) {
      throw FormatException('不正なバックアップ内アプリID: $id');
    }
  }

  static Map<String, dynamic> _validateValues(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('保存データはJSONオブジェクトである必要があります');
    }
    final values = <String, dynamic>{};
    for (final item in raw.entries) {
      final key = item.key;
      if (key is! String || key.isEmpty || key.length > 100) {
        throw const FormatException('保存キーの長さが不正です');
      }
      values[key] = item.value;
    }
    if (utf8.encode(jsonEncode(values)).length > maxAppBytes) {
      throw const FormatException('1アプリの保存データは1MiBまでです');
    }
    return values;
  }

  /// Create a portable snapshot; files left by a removed app are included.
  Future<Uint8List> exportData() async {
    await dataRoot.create(recursive: true);
    final records = <Map<String, dynamic>>[];
    await for (final entry in dataRoot.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) { continue; }
      final id = p.basenameWithoutExtension(entry.path);
      _checkId(id);
      if (await entry.length() > maxAppBytes) {
        throw FormatException('保存データが大きすぎます: $id');
      }
      final values = _validateValues(jsonDecode(await entry.readAsString()));
      records.add({'id': id, 'values': values});
    }
    if (records.length > maxApps) {
      throw const FormatException('バックアップ可能なアプリは100件までです');
    }
    records.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final data = utf8.encode(jsonEncode({
      'type': 'chappy-data-backup',
      'formatVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'apps': records,
    }));
    if (data.length > maxBytes) {
      throw const FormatException('バックアップの最大サイズは12MiBです');
    }
    return Uint8List.fromList(data);
  }

  /// Fully validate before touching disk.
  BackupSnapshot inspect(Uint8List bytes) => inspectBackup(bytes);

  /// Validate portable backup data without needing access to storage files.
  static BackupSnapshot inspectBackup(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('バックアップは12MiB以下である必要があります');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'chappy-data-backup' ||
        decoded['formatVersion'] != 1 ||
        decoded['apps'] is! List) {
      throw const FormatException('対応していないバックアップ形式です');
    }
    final createdAt = decoded['createdAt'];
    if (createdAt is! String || createdAt.length > 80) {
      throw const FormatException('バックアップの日時が不正です');
    }
    final list = decoded['apps'] as List;
    if (list.length > maxApps) {
      throw const FormatException('バックアップの件数が多すぎます');
    }
    final apps = <String, Map<String, dynamic>>{};
    for (final item in list) {
      if (item is! Map<String, dynamic> || item['id'] is! String) {
        throw const FormatException('バックアップのアプリ情報が不正です');
      }
      final id = item['id'] as String;
      _checkId(id);
      if (apps.containsKey(id)) {
        throw FormatException('重複したアプリID: $id');
      }
      apps[id] = _validateValues(item['values']);
    }
    return BackupSnapshot(apps, createdAt);
  }

  /// If a restore was interrupted, roll back to the pre-restore data.
  /// A completed restore is left intact, and only its staging is removed.
  Future<void> recoverInterruptedRestore() async {
    if (!await _pending.exists()) { return; }
    final completed = File(p.join(_pending.path, 'COMPLETED'));
    final ready = File(p.join(_pending.path, 'READY'));
    if (await completed.exists() || !await ready.exists()) {
      await _pending.delete(recursive: true);
      return;
    }
    final plan = File(p.join(_pending.path, 'plan.json'));
    if (!await plan.exists()) {
      throw const FormatException('保存データ復旧計画がありません');
    }
    final ids = jsonDecode(await plan.readAsString());
    if (ids is! List || ids.length > maxApps) {
      throw const FormatException('保存データ復旧計画が破損しています');
    }
    await dataRoot.create(recursive: true);
    for (final value in ids) {
      if (value is! String) {
        throw const FormatException('復旧計画のIDが不正です');
      }
      _checkId(value);
      final destination = File(p.join(dataRoot.path, '$value.json'));
      final previous = File(p.join(_pending.path, 'old', '$value.json'));
      if (await previous.exists()) {
        final temp = File('${destination.path}.restore_tmp');
        await temp.writeAsBytes(await previous.readAsBytes(), flush: true);
        await temp.rename(destination.path);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    }
    await _pending.delete(recursive: true);
  }

  /// Restore all saved entries. Existing data for matching IDs is replaced.
  /// Call inspect() and show a user confirmation before invoking this.
  Future<int> restore(Uint8List bytes) async {
    final snapshot = inspect(bytes);
    await recoverInterruptedRestore();
    await dataRoot.create(recursive: true);
    await _pending.create(recursive: true);
    final newDir = Directory(p.join(_pending.path, 'new'));
    final oldDir = Directory(p.join(_pending.path, 'old'));
    await newDir.create(recursive: true);
    await oldDir.create(recursive: true);
    try {
      for (final item in snapshot.apps.entries) {
        final destination = File(p.join(dataRoot.path, '${item.key}.json'));
        if (await destination.exists()) {
          await destination.copy(p.join(oldDir.path, '${item.key}.json'));
        }
        await File(p.join(newDir.path, '${item.key}.json'))
            .writeAsString(jsonEncode(item.value), flush: true);
      }
      final ids = snapshot.ids;
      await File(p.join(_pending.path, 'plan.json'))
          .writeAsString(jsonEncode(ids), flush: true);
      await File(p.join(_pending.path, 'READY')).writeAsString('ready', flush: true);
      for (final id in ids) {
        final source = File(p.join(newDir.path, '$id.json'));
        final target = File(p.join(dataRoot.path, '$id.json'));
        final temp = File('${target.path}.restore_tmp');
        await source.copy(temp.path);
        await temp.rename(target.path);
      }
      await File(p.join(_pending.path, 'COMPLETED'))
          .writeAsString('complete', flush: true);
      await _pending.delete(recursive: true);
      return ids.length;
    } catch (_) {
      await recoverInterruptedRestore();
      rethrow;
    }
  }
}
