import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/package_model.dart';

/// Validate the central directory BEFORE calling an archive decompressor.
/// v1 deliberately rejects Zip64, encrypted ZIPs and non-ASCII paths.
void validateZipEnvelope(Uint8List input) {
  const maxZipBytes = 12 * 1024 * 1024;
  const maxUnpackedBytes = 24 * 1024 * 1024;
  if (input.length > maxZipBytes || input.length < 22) {
    throw const FormatException('ZIPは12MiB以下である必要があります');
  }
  final data = ByteData.sublistView(input);
  int u16(int o) => data.getUint16(o, Endian.little);
  int u32(int o) => data.getUint32(o, Endian.little);
  int eocd = -1;
  final start = input.length - 22;
  final stop = input.length - 22 - 65535;
  for (var i = start; i >= (stop < 0 ? 0 : stop); i--) {
    if (u32(i) == 0x06054b50 && i + 22 + u16(i + 20) == input.length) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException('ZIPの終端ヘッダーがありません');
  final disk = u16(eocd + 4);
  final diskOfCd = u16(eocd + 6);
  final countOnDisk = u16(eocd + 8);
  final count = u16(eocd + 10);
  final centralSize = u32(eocd + 12);
  final centralStart = u32(eocd + 16);
  if (disk != 0 || diskOfCd != 0 || countOnDisk != count ||
      count == 0 || count > 200 || count == 0xffff ||
      centralSize == 0xffffffff || centralStart == 0xffffffff ||
      centralStart + centralSize > eocd) {
    throw const FormatException('未対応または不正なZIP構造です');
  }
  var offset = centralStart;
  var totalUnpacked = 0;
  final seen = <String>{};
  for (var index = 0; index < count; index++) {
    if (offset + 46 > eocd || u32(offset) != 0x02014b50) {
      throw const FormatException('ZIP中央ディレクトリが破損しています');
    }
    final flags = u16(offset + 8);
    final method = u16(offset + 10);
    final compressed = u32(offset + 20);
    final unpacked = u32(offset + 24);
    final nameLength = u16(offset + 28);
    final extraLength = u16(offset + 30);
    final commentLength = u16(offset + 32);
    final mode = u32(offset + 38) >> 16;
    final localOffset = u32(offset + 42);
    final end = offset + 46 + nameLength + extraLength + commentLength;
    if (end > eocd || localOffset >= centralStart ||
        compressed == 0xffffffff || unpacked == 0xffffffff ||
        (flags & 1) != 0 || (method != 0 && method != 8)) {
      throw const FormatException('暗号化・Zip64・特殊圧縮は使用できません');
    }
    if ((mode & 0xf000) == 0xa000) {
      throw const FormatException('シンボリックリンクは使用できません');
    }
    final nameBytes = input.sublist(offset + 46, offset + 46 + nameLength);
    if (nameBytes.any((c) => c > 127)) {
      throw const FormatException('v1ではZIP内ファイル名はASCIIのみ対応です');
    }
    final name = ascii.decode(nameBytes);
    if (!isSafeArchivePath(name) ||
        name == '__chappy_boot.js' || name == '__chappy_media.js') {
      throw FormatException('安全でないパス: $name');
    }
    if (!seen.add(name.toLowerCase())) {
      throw FormatException('重複するZIP内パス: $name');
    }
    totalUnpacked += unpacked;
    if (unpacked > 10 * 1024 * 1024 || totalUnpacked > maxUnpackedBytes ||
        (compressed == 0 && unpacked > 0) ||
        (compressed > 0 && unpacked > compressed * 250)) {
      throw const FormatException('展開サイズ・圧縮率が安全上限を超えます');
    }
    offset = end;
  }
  if (offset != centralStart + centralSize) {
    throw const FormatException('中央ディレクトリの長さが一致しません');
  }
  if (!seen.contains('manifest.json') || !seen.contains('index.html')) {
    throw const FormatException('manifest.json または index.html がありません');
  }
}
