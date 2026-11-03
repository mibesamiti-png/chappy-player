import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chappy_player/core/package_model.dart';
import 'package:chappy_player/core/zip_preflight.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PackageRepository {
  late final Directory root;
  late final Directory appsRoot;
  late final Directory dataRoot;
  late final Directory stagingRoot;
  late final File registryFile;
  final Map<String, ChappyPackage> _apps = {};

  List<ChappyPackage> get apps {
    final result = _apps.values.toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  bool hasApp(String id) => _apps.containsKey(id);
  Directory currentDir(String id) => Directory(p.join(appsRoot.path, id, 'current'));
  Directory previousDir(String id) => Directory(p.join(appsRoot.path, id, 'previous'));

  Future<void> init() async {
    final doc = await getApplicationDocumentsDirectory();
    root = Directory(p.join(doc.path, 'chappy_library'));
    appsRoot = Directory(p.join(root.path, 'apps'));
    dataRoot = Directory(p.join(root.path, 'data'));
    stagingRoot = Directory(p.join(root.path, 'staging'));
    registryFile = File(p.join(root.path, 'library.json'));
    await appsRoot.create(recursive: true);
    await dataRoot.create(recursive: true);
    await stagingRoot.create(recursive: true);
    if (await registryFile.exists()) {
      try {
        final data = jsonDecode(await registryFile.readAsString()) as List<dynamic>;
        for (final entry in data) {
          final app = ChappyPackage.fromJson(Map<String, dynamic>.from(entry as Map));
          if (await currentDir(app.id).exists()) _apps[app.id] = app;
        }
      } catch (_) {
        throw const FormatException('アプリ一覧のデータが破損しています。削除せず診断してください');
      }
    }
    // Clean only orphaned staging directories, never live app data.
    await for (final entry in stagingRoot.list()) {
      if (entry is Directory) await entry.delete(recursive: true);
    }
  }

  Future<ChappyPackage> install(Uint8List zipBytes) async {
    validateZipEnvelope(zipBytes);
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final manifestEntry = archive.files.firstWhere((entry) => entry.name == 'manifest.json');
    final app = ChappyPackage.parse(utf8.decode(manifestEntry.readBytes() ?? (throw const FormatException('manifest.jsonが読み取れません'))));
    final stage = await Directory(p.join(
      stagingRoot.path, 'new_${DateTime.now().microsecondsSinceEpoch}',
    )).create(recursive: true);
    try {
      for (final entry in archive) {
        final name = entry.name;
        // Path validation was performed before ZIP decoding too.
        if (!isSafeArchivePath(name)) throw const FormatException('不正なZIP内パス');
        final target = p.join(stage.path, p.joinAll(name.split('/')));
        if (entry.isFile) {
          final file = File(target);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.readBytes() ?? (throw const FormatException('ZIP内のファイルが読み取れません')), flush: true);
        } else {
          await Directory(target).create(recursive: true);
        }
      }
      final current = currentDir(app.id);
      final previous = previousDir(app.id);
      await current.parent.create(recursive: true);
      if (await previous.exists()) await previous.delete(recursive: true);
      final didHaveCurrent = await current.exists();
      if (didHaveCurrent) await current.rename(previous.path);
      try {
        await stage.rename(current.path);
        _apps[app.id] = app;
        await _saveRegistry();
      } catch (_) {
        if (await current.exists()) await current.delete(recursive: true);
        if (didHaveCurrent && await previous.exists()) {
          await previous.rename(current.path);
        }
        _apps.remove(app.id);
        if (didHaveCurrent && await current.exists()) {
          final oldManifest = File(p.join(current.path, 'manifest.json'));
          _apps[app.id] = ChappyPackage.parse(await oldManifest.readAsString());
        }
        rethrow;
      }
      return app;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Future<void> rollback(String id) async {
    final current = currentDir(id);
    final previous = previousDir(id);
    if (!await previous.exists()) throw const FormatException('戻せる旧バージョンがありません');
    final old = ChappyPackage.parse(
      await File(p.join(previous.path, 'manifest.json')).readAsString(),
    );
    final swap = Directory(p.join(stagingRoot.path, 'swap_${DateTime.now().microsecondsSinceEpoch}'));
    await current.rename(swap.path);
    try {
      await previous.rename(current.path);
      await swap.rename(previous.path);
      _apps[id] = old;
      await _saveRegistry();
    } catch (_) {
      // Keep both versions rather than deleting user data on unexpected IO errors.
      rethrow;
    }
  }

  Future<bool> canRollback(String id) => previousDir(id).exists();

  Future<void> remove(String id, {required bool deleteData}) async {
    final rootDir = Directory(p.join(appsRoot.path, id));
    if (await rootDir.exists()) await rootDir.delete(recursive: true);
    if (deleteData) {
      final data = File(p.join(dataRoot.path, '$id.json'));
      if (await data.exists()) await data.delete();
    }
    _apps.remove(id);
    await _saveRegistry();
  }

  Future<void> _saveRegistry() async {
    final tmp = File('${registryFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(_apps.values.map((e) => e.toJson()).toList()), flush: true);
    await tmp.rename(registryFile.path);
  }
}
