import 'dart:io';

/// One offline, owner-provided BUFFALO router client-monitor snapshot.
/// Presence in a list is not proof of Android OS or unauthorized access.
class RouterInventoryEntry {
  final String? ip;
  final String? mac;
  final String? hostname;

  const RouterInventoryEntry({
    this.ip,
    this.mac,
    this.hostname,
  });

  String get identity => mac ?? ip ?? '';
}

/// Import from owner-copied client-monitor rows only; no network access.
class BuffaloClientInventoryParser {
  static const maxInputLength = 32768;
  static const maxLines = 256;
  static const maxDevices = 128;

  static final RegExp _macPattern = RegExp(
    r'(?<![0-9a-fA-F])(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}(?![0-9a-fA-F])',
  );
  static final RegExp _bareMacPattern =
      RegExp(r'(?<![0-9a-fA-F])[0-9a-fA-F]{12}(?![0-9a-fA-F])');
  static final RegExp _ipPattern =
      RegExp(r'(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])');

  static String? normalizeMac(String raw) {
    final digits = raw.replaceAll(RegExp(r'[:-]'), '').toUpperCase();
    if (digits.length != 12 || RegExp(r'[^0-9A-F]').hasMatch(digits)) {
      return null;
    }
    return List.generate(6, (i) => digits.substring(i * 2, i * 2 + 2))
        .join(':');
  }

  static String? privateIp(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null || address.type != InternetAddressType.IPv4 ||
        value != address.address) {
      return null;
    }
    final b = address.rawAddress;
    if (b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168)) {
      return address.address;
    }
    return null;
  }

  static List<RouterInventoryEntry> parse(String data) {
    if (data.length > maxInputLength) {
      throw const FormatException('端末一覧は32KiBまでです');
    }
    final rows = data.split(RegExp(r'\r?\n'));
    if (rows.length > maxLines) {
      throw const FormatException('端末一覧の行数が多すぎます');
    }
    final entries = <RouterInventoryEntry>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row.length > 512) continue;
      final line = row.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final macMatches = _macPattern.allMatches(line).toList();
      final bareMatches = macMatches.isEmpty
          ? _bareMacPattern.allMatches(line).toList()
          : <RegExpMatch>[];
      final ipMatches = _ipPattern.allMatches(line).toList();
      if (macMatches.length + bareMatches.length > 1 || ipMatches.length > 1) {
        continue;
      }
      final macHit = macMatches.isNotEmpty
          ? macMatches.single
          : (bareMatches.isNotEmpty ? bareMatches.single : null);
      final mac = macHit == null ? null : normalizeMac(macHit.group(0)!);
      final ipHit = ipMatches.isEmpty ? null : ipMatches.single;
      final ip = ipHit == null ? null : privateIp(ipHit.group(0)!);
      if (mac == null && ip == null) continue;

      var rest = line;
      if (macHit != null) {
        rest = rest.replaceFirst(macHit.group(0)!, ' ');
      }
      if (ipHit != null) {
        rest = rest.replaceFirst(ipHit.group(0)!, ' ');
      }
      rest = rest.replaceAll(RegExp(r'[,\t|;]'), ' ').trim();
      if (rest.contains(RegExp(r'[\x00-\x1f\x7f]'))) continue;
      final hostname = rest.isEmpty || rest.length > 64 ||
              rest.contains('<') || rest.contains('>') ||
              rest.contains('://') || rest.contains('=') ||
              rest.startsWith('MAC') || rest.startsWith('IPアドレス')
          ? null
          : rest;

      final identity = mac ?? ip!;
      if (!seen.add(identity)) continue;
      if (entries.length >= maxDevices) {
        throw const FormatException('表示できる端末は128台までです');
      }
      entries.add(RouterInventoryEntry(mac: mac, ip: ip, hostname: hostname));
    }
    return List.unmodifiable(entries);
  }
}
