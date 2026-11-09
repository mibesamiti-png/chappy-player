import 'dart:io';

import 'package:flutter/services.dart';

/// A one-shot host-only Android Wi-Fi router identification probe.
/// UPnP fields are untrusted device-advertised hints, NOT verified identities.
class RouterIdentitySnapshot {
  final String gatewayIpv4;
  final String evidence;
  final String? manufacturer;
  final String? modelName;
  final String? modelNumber;
  final String? friendlyName;

  const RouterIdentitySnapshot({
    required this.gatewayIpv4,
    required this.evidence,
    required this.manufacturer,
    required this.modelName,
    required this.modelNumber,
    required this.friendlyName,
  });

  bool get hasAdvertisedIdentity =>
      evidence == 'upnp_self_report' &&
      (manufacturer != null || modelName != null || modelNumber != null);

  static bool isPrivateIpv4(String raw) {
    final ip = InternetAddress.tryParse(raw);
    if (ip == null || ip.type != InternetAddressType.IPv4 ||
        ip.address != raw) {
      return false;
    }
    final b = ip.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  static String? _displayLabel(dynamic value) {
    if (value is! String || value.trim().isEmpty || value.length > 96) {
      return null;
    }
    if (value.contains(RegExp(r'[\x00-\x1F\x7F<>]')) ||
        value.contains('://')) {
      return null;
    }
    return value.trim();
  }

  factory RouterIdentitySnapshot.fromWire(Map<dynamic, dynamic>? wire) {
    if (wire == null || wire['gatewayIpv4'] is! String) {
      throw const FormatException('Missing Android Wi-Fi gateway');
    }
    final gateway = wire['gatewayIpv4'] as String;
    if (!isPrivateIpv4(gateway) ||
        wire['source'] != 'android_wifi_default_route') {
      throw const FormatException('Invalid router default-route evidence');
    }
    final evidence = wire['evidence'];
    if (evidence != 'upnp_self_report' && evidence != 'gateway_only') {
      throw const FormatException('Unsupported router identification evidence');
    }
    if (evidence == 'gateway_only' &&
        (wire['manufacturer'] != '' || wire['modelName'] != '' ||
         wire['modelNumber'] != '' || wire['friendlyName'] != '')) {
      throw const FormatException('Gateway-only response must not claim a model');
    }
    return RouterIdentitySnapshot(
      gatewayIpv4: gateway,
      evidence: evidence as String,
      manufacturer: _displayLabel(wire['manufacturer']),
      modelName: _displayLabel(wire['modelName']),
      modelNumber: _displayLabel(wire['modelNumber']),
      friendlyName: _displayLabel(wire['friendlyName']),
    );
  }
}

/// Uses the existing privileged native host channel, never the mini-app bridge.
class RouterIdentityClient {
  final MethodChannel _channel;

  const RouterIdentityClient({
    MethodChannel channel = const MethodChannel('dev.chappy.player/network_lab'),
  }) : _channel = channel;

  Future<RouterIdentitySnapshot> probe() async {
    final wire =
        await _channel.invokeMapMethod<String, dynamic>('routerIdentityProbe');
    return RouterIdentitySnapshot.fromWire(wire);
  }
}
