import 'package:chappy_player/core/openwrt_router_client.dart';
import 'package:chappy_player/core/router_connection_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pin = 'a' * 64;

  test('router credentials require IPv4 LAN and pinned HTTPS', () {
    OpenWrtRouterClient.validateRouter(
      ip: '192.168.1.1', port: 443, tlsFingerprint: pin,
      deviceIp: '192.168.1.20',
      username: 'readonly', password: 'test-not-a-real-password',
    );
    for (final router in ['8.8.8.8', '127.0.0.1', '169.254.2.1',
                           '192.168.0.1.evil', '::1']) {
      expect(() => OpenWrtRouterClient.validateRouter(
        ip: router, port: 443, tlsFingerprint: pin,
        deviceIp: '192.168.1.20',
        username: 'readonly', password: 'test',
      ), throwsFormatException);
    }
    expect(() => OpenWrtRouterClient.validateRouter(
      ip: '192.168.1.1', port: 443, tlsFingerprint: 'short',
      deviceIp: '192.168.1.20', username: 'readonly', password: 'test',
    ), throwsFormatException);
    expect(() => OpenWrtRouterClient.validateRouter(
      ip: '192.168.1.1', port: 443, tlsFingerprint: pin,
      deviceIp: '8.8.8.8', username: 'readonly', password: 'test',
    ), throwsFormatException);
  });

  test('target only: never mix conntrack from another Android or LAN device',
      () {
    final snapshot = RouterConntrackContract.parse(
      deviceIp: '192.168.1.20',
      rawLeases: {
        'dhcp_leases': [
          {'ipaddr': '192.168.1.20', 'hostname': 'Owner-Pixel'},
          {'ipaddr': '192.168.1.21', 'hostname': 'Other-Device'},
        ],
      },
      rawList: [
        {
          'src': '192.168.1.20', 'dst': '203.0.113.10',
          'dport': 443, 'sport': 51111, 'layer4': 'tcp',
        },
        {
          'src': '192.168.1.21', 'dst': '198.51.100.25',
          'dport': 443, 'layer4': 'udp',
        },
        {
          'src': '192.168.1.20', 'dst': '192.168.1.1',
          'dport': 53, 'layer4': 'udp',
        },
        // A reply direction can NOT be attributed to this device.
        {
          'src': '203.0.113.10', 'dst': '192.168.1.20',
          'dport': 51111, 'layer4': 'tcp',
        },
        {
          'src': '192.168.1.20', 'dst': '203.0.113.10',
          'dport': 443, 'layer4': 'tcp',
        },
      ],
    );
    expect(snapshot.deviceName, 'Owner-Pixel');
    expect(snapshot.connections.length, 2);
    expect(snapshot.connections.map((e) => e.destinationIp),
        contains('203.0.113.10'));
    expect(snapshot.connections.map((e) => e.destinationIp),
        isNot(contains('198.51.100.25')));
    expect(snapshot.truncated, isFalse);
  });

  test('never parse raw packets, invalid ports or arbitrary protocols', () {
    final snapshot = RouterConntrackContract.parse(
      deviceIp: '10.0.0.10',
      rawList: [
        {'src': '10.0.0.10', 'dst': '198.51.100.1',
         'dport': -1, 'layer4': 'tcp', 'payload': 'secret'},
        {'src': '10.0.0.10', 'dst': '198.51.100.1',
         'dport': 443, 'layer4': 'unknown'},
        {'src': '10.0.0.10', 'dst': '127.0.0.1',
         'dport': 443, 'layer4': 'tcp'},
        {'src': '10.0.0.10', 'dst': '198.51.100.1',
         'dport': 443, 'layer4': 'tcp', 'payload': 'ignored'},
      ],
    );
    expect(snapshot.connections.length, 1);
    expect(snapshot.connections.single.destinationIp, '198.51.100.1');
  });

  test('bounded router rows, visible destination list and DHCP hints', () {
    expect(() => RouterConntrackContract.parse(
      deviceIp: '192.168.1.20',
      rawList: List.filled(1201, <String, Object?>{}),
    ), throwsFormatException);
    final snapshot = RouterConntrackContract.parse(
      deviceIp: '192.168.1.20',
      rawLeases: {
        'dhcp_leases': [
          {'ipaddr': '192.168.1.20', 'hostname': 'owner'}
        ]
      },
      rawList: List.generate(150, (i) => {
        'src': '192.168.1.20',
        'dst': '203.0.113.${i + 1}',
        'dport': 443,
        'layer4': 'tcp',
      }),
    );
    expect(snapshot.connections.length, RouterConntrackContract.maxVisible);
    expect(snapshot.truncated, isTrue);
    expect(snapshot.deviceName, 'owner');
  });
}
