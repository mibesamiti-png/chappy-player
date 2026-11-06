import 'package:flutter/services.dart';

/// Host-only Android NSD adapter. Not exposed to .chappy mini-app JavaScript.
class LanDiscoveryClient {
  static const supportedTypes = <String>{
    '_http._tcp.',
    '_workstation._tcp.',
    '_ipp._tcp.',
  };

  final MethodChannel _channel;
  const LanDiscoveryClient({
    MethodChannel channel =
        const MethodChannel('dev.chappy.player/network_lab'),
  }) : _channel = channel;

  Future<LanDiscoverySnapshot> start(String serviceType) async {
    if (!supportedTypes.contains(serviceType)) {
      throw const FormatException('Unsupported DNS-SD service type');
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'start',
      <String, dynamic>{'serviceType': serviceType},
    );
    return LanDiscoverySnapshot.fromWire(result);
  }

  Future<LanDiscoverySnapshot> snapshot() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('snapshot');
    return LanDiscoverySnapshot.fromWire(result);
  }

  Future<LanDiscoverySnapshot> stop() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('stop');
    return LanDiscoverySnapshot.fromWire(result);
  }
}

class LanDiscoveredService {
  final String id;
  final String name;
  final String type;
  final String address;
  final int port;
  final bool resolved;

  const LanDiscoveredService({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.port,
    required this.resolved,
  });

  factory LanDiscoveredService.fromWire(Map<dynamic, dynamic> map) =>
      LanDiscoveredService(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        type: (map['type'] as String?) ?? '',
        address: (map['address'] as String?) ?? '',
        port: (map['port'] as num?)?.toInt() ?? 0,
        resolved: map['resolved'] == true,
      );
}

class LanDiscoverySnapshot {
  final bool running;
  final String serviceType;
  final int remainingSeconds;
  final String? error;
  final List<LanDiscoveredService> services;

  const LanDiscoverySnapshot({
    required this.running,
    required this.serviceType,
    required this.remainingSeconds,
    required this.error,
    required this.services,
  });

  factory LanDiscoverySnapshot.fromWire(Map<String, dynamic>? map) {
    if (map == null) throw const FormatException('Missing NSD result');
    final items = map['services'];
    if (items is! List) throw const FormatException('Invalid NSD service list');
    return LanDiscoverySnapshot(
      running: map['running'] == true,
      serviceType: (map['serviceType'] as String?) ?? '_http._tcp.',
      remainingSeconds: (map['remainingSeconds'] as num?)?.toInt() ?? 0,
      error: map['error'] as String?,
      services: items
          .whereType<Map>()
          .take(24)
          .map((item) => LanDiscoveredService.fromWire(item))
          .toList(growable: false),
    );
  }
}
