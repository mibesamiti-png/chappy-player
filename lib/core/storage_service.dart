import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class StorageService {
  final Directory dataRoot;
  StorageService(this.dataRoot);
  Future<void> _pendingWrite = Future<void>.value();

  File _file(String id) => File(p.join(dataRoot.path, '$id.json'));

  Future<Map<String, dynamic>> _load(String id) async {
    final file = _file(id);
    if (!await file.exists()) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
    } catch (_) {
      throw const FormatException('保存データを読み込めませんでした（破損の可能性）');
    }
  }

  Future<dynamic> get(String id, String key) async {
    _checkKey(key);
    await _pendingWrite;
    return (await _load(id))[key];
  }

  Future<void> set(String id, String key, dynamic value) => _serialize(() async {
    _checkKey(key);
    final current = await _load(id);
    current[key] = value;
    final bytes = utf8.encode(jsonEncode(current));
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('アプリの保存データ上限（1MiB）を超えます');
    }
    await _atomicWrite(_file(id), bytes);
  });

  Future<void> remove(String id, String key) => _serialize(() async {
    _checkKey(key);
    final current = await _load(id);
    current.remove(key);
    await _atomicWrite(_file(id), utf8.encode(jsonEncode(current)));
  });

  Future<void> _serialize(Future<void> Function() action) {
    final result = _pendingWrite.then((_) => action());
    _pendingWrite = result.catchError((Object _) {});
    return result;
  }

  void _checkKey(String key) {
    if (key.isEmpty || key.length > 100) {
      throw const FormatException('保存キーは1〜100文字です');
    }
  }

  Future<void> _atomicWrite(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}
