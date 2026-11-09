import 'dart:io';

/// One foreground snapshot of explicitly authorized LAN client connections.
/// Router-provided names are hints, never proof of Android OS or ownership.
class RouterConnection {
  final String destinationIp;
  final int destinationPort;
  final String protocol;
  final int? bytes;
  const RouterConnection({
    required this.destinationIp,
    required this.destinationPort,
    required this.protocol,
    this.bytes,
  });
}

class RouterConnectionSnapshot {
  final String deviceIp;
  final String? deviceName;
  final List<RouterConnection> connections;
  final bool truncated;
  const RouterConnectionSnapshot({
    required this.deviceIp,
    required this.deviceName,
    required this.connections,
    required this.truncated,
  });
}

/// OpenWrt LuCI RPC contracts. Never parses packet contents or reverse DNS.
/// Do not interpret active conntrack rows as browser history or application use.
class RouterConntrackContract {
  static const maxRows = 1200;
  static const maxVisible = 120;
  static const maxReplyBytes = 256 * 1024;

  static bool isPrivateIpv4(String value) {
    final ip = InternetAddress.tryParse(value);
    if (ip == null || ip.type != InternetAddressType.IPv4 ||
        value.trim() != value) {
      return false;
    }
    final bytes = ip.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static bool isDestinationIp(String value) {
    final ip = InternetAddress.tryParse(value);
    if (ip == null || ip.isLoopback || ip.isLinkLocal || ip.isMulticast ||
        (ip.address == '0.0.0.0' || ip.address == '::') ||
        value.trim() != value) {
      return false;
    }
    return ip.type == InternetAddressType.IPv4 ||
        ip.type == InternetAddressType.IPv6;
  }

  static String? deviceNameFor(
      Object? rawLeases, String targetIp) {
    if (rawLeases is! Map || rawLeases['dhcp_leases'] is! List) {
      return null;
    }
    final leases = rawLeases['dhcp_leases'] as List;
    if (leases.length > 512) {
      throw const FormatException('ルーターの端末一覧が大きすぎます');
    }
    for (final item in leases) {
      if (item is! Map || item['ipaddr'] != targetIp) continue;
      final name = item['hostname'];
      if (name is String && name.isNotEmpty && name.length <= 64 &&
          !name.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        return name;
      }
    }
    return null;
  }

  static RouterConnectionSnapshot parse({
    required String deviceIp,
    required Object? rawList,
    Object? rawLeases,
  }) {
    if (!isPrivateIpv4(deviceIp)) {
      throw const FormatException('対象端末は私有IPv4アドレスに限定します');
    }
    if (rawList is! List || rawList.length > maxRows) {
      throw const FormatException('ルーターの接続一覧が大きすぎるか不正です');
    }
    final seen = <String>{};
    final output = <RouterConnection>[];
    var totalMatches = 0;
    for (final item in rawList) {
      if (item is! Map) continue;
      // The original conntrack direction names the LAN initiator.
      // Never attribute a reverse NAT/reply-side row to another device.
      if (item['src'] != deviceIp) continue;
      final dst = item['dst'];
      final proto = item['layer4'];
      final rawPort = item['dport'];
      final dport = rawPort is int ? rawPort :
          (rawPort is String && RegExp(r'^[0-9]{1,5}$').hasMatch(rawPort)
              ? int.tryParse(rawPort) : null);
      if (dst is! String || !isDestinationIp(dst) ||
          proto is! String ||
          !const {'tcp', 'udp', 'icmp', 'icmpv6'}.contains(proto) ||
          dport == null || dport < 0 || dport > 65535) {
        continue;
      }
      if ((proto == 'tcp' || proto == 'udp') && dport == 0) continue;
      final key = '$proto|$dst|$dport';
      if (!seen.add(key)) continue;
      totalMatches++;
      if (output.length >= maxVisible) continue;
      final rawBytes = item['bytes'];
      final count = rawBytes is int ? rawBytes :
          (rawBytes is String && RegExp(r'^[0-9]{1,16}$').hasMatch(rawBytes)
              ? int.tryParse(rawBytes) : null);
      final bytes = count != null && count >= 0 &&
          count <= 0x1fffffffffffff ? count : null;
      output.add(RouterConnection(
        destinationIp: dst,
        destinationPort: dport,
        protocol: proto.toUpperCase(),
        bytes: bytes,
      ));
    }
    return RouterConnectionSnapshot(
      deviceIp: deviceIp,
      deviceName: deviceNameFor(rawLeases, deviceIp),
      connections: List.unmodifiable(output),
      truncated: totalMatches > maxVisible,
    );
  }
}
