import 'dart:convert';
import 'dart:typed_data';

import 'package:chappy_player/core/pcap_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void _put16(List<int> b, int value) {
  b.add(value & 255);
  b.add((value >> 8) & 255);
}

void _put32(List<int> b, int value) {
  b.add(value & 255);
  b.add((value >> 8) & 255);
  b.add((value >> 16) & 255);
  b.add((value >> 24) & 255);
}

List<int> _ipPacket({
  required bool tcp,
  required int sourcePort,
  required int destPort,
  required List<int> payload,
}) {
  final ip = <int>[
    0x45, 0, 0, 0, 0, 1, 0, 0, 64, tcp ? 6 : 17, 0, 0,
    192, 168, 11, 10, 93, 184, 215, 14,
  ];
  final transport = tcp
      ? <int>[
          sourcePort >> 8, sourcePort & 255,
          destPort >> 8, destPort & 255,
          0, 0, 0, 1, 0, 0, 0, 0, 0x50, 0x18, 0, 0, 0, 0, 0, 0,
        ]
      : <int>[
          sourcePort >> 8, sourcePort & 255,
          destPort >> 8, destPort & 255,
          0, 8 + payload.length, 0, 0,
        ];
  final size = ip.length + transport.length + payload.length;
  ip[2] = size >> 8;
  ip[3] = size & 255;
  return [...ip, ...transport, ...payload];
}

Uint8List _pcap(List<List<int>> packets) {
  final b = <int>[0xd4, 0xc3, 0xb2, 0xa1];
  _put16(b, 2);
  _put16(b, 4);
  _put32(b, 0);
  _put32(b, 0);
  _put32(b, 65535);
  _put32(b, 101); // raw IPv4
  for (final packet in packets) {
    _put32(b, 0);
    _put32(b, 0);
    _put32(b, packet.length);
    _put32(b, packet.length);
    b.addAll(packet);
  }
  return Uint8List.fromList(b);
}

void main() {
  test('HTTP destination and host, query excluded, plaintext off by default', () {
    final data = _pcap([
      _ipPacket(
        tcp: true,
        sourcePort: 50000,
        destPort: 80,
        payload: ascii.encode(
          'POST /submit?token=secret HTTP/1.1\r\n'
          'Host: example.org\r\n'
          'Content-Type: text/plain\r\n\r\nhello world',
        ),
      ),
    ]);
    final noBody = PcapInspector.parseBytes(data);
    expect(noBody.packetCount, 1);
    expect(noBody.observations, hasLength(1));
    expect(noBody.observations.single.sourceIp, '192.168.11.10');
    expect(noBody.observations.single.destinationIp, '93.184.215.14');
    expect(noBody.observations.single.destinationPort, 80);
    expect(noBody.observations.single.description, '平文HTTP POST /submit');
    expect(noBody.observations.single.hostHint, 'example.org');
    expect(noBody.observations.single.plaintextPreview, isNull);
    final optIn = PcapInspector.parseBytes(data, includePlaintextBody: true);
    expect(optIn.observations.single.plaintextPreview, 'hello world');
  });

  test('plain HTTP payload resembling secrets is not displayed even opt-in', () {
    final data = _pcap([
      _ipPacket(tcp: true, sourcePort: 50001, destPort: 80,
          payload: ascii.encode(
            'POST /login HTTP/1.1\r\nHost: sample.test\r\n'
            'Content-Type: application/json\r\n\r\n'
            '{"password":"dont-display"}',
          )),
    ]);
    final x = PcapInspector.parseBytes(data, includePlaintextBody: true);
    expect(x.observations.single.plaintextPreview,
        '[機微情報の可能性があるため非表示]');
  });

  test('DNS question displayed without asserting actual visited website', () {
    final dns = <int>[
      0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
      7, ...ascii.encode('example'),
      3, ...ascii.encode('com'),
      0, 0, 1, 0, 1,
    ];
    final data = _pcap([
      _ipPacket(tcp: false, sourcePort: 40500, destPort: 53,
          payload: dns),
    ]);
    final result = PcapInspector.parseBytes(data);
    expect(result.observations.single.hostHint, 'example.com');
    expect(result.observations.single.description, contains('DNS問い合わせ'));
  });

  test('TCP port 443 does not fabricate decrypted HTTPS text', () {
    final data = _pcap([
      _ipPacket(tcp: true, sourcePort: 42222, destPort: 443,
          payload: [1, 2, 3, 4, 5]),
    ]);
    final result = PcapInspector.parseBytes(
        data, includePlaintextBody: true);
    expect(result.observations.single.encrypted, isTrue);
    expect(result.observations.single.plaintextPreview, isNull);
    expect(result.observations.single.description, contains('本文は読めません'));
  });

  test('invalid classic PCAP header and record lengths fail closed', () {
    final a = _pcap([]);
    a[0] = 0x0a; // PCAPNG marker
    expect(() => PcapInspector.parseBytes(a), throwsFormatException);
    final b = _pcap([
      _ipPacket(tcp: false, sourcePort: 1234, destPort: 53,
          payload: [1, 2, 3]),
    ]);
    b[24 + 8] = 255; // claim more data than present
    expect(() => PcapInspector.parseBytes(b), throwsFormatException);
    final c = _pcap([]);
    c[20] = 255; // unsupported link type
    expect(() => PcapInspector.parseBytes(c), throwsFormatException);
    expect(() => PcapInspector.parseBytes(Uint8List(0)),
        throwsFormatException);
  });

  test('2500 packet cap and display cap, no unbounded parsing', () {
    final packet = _ipPacket(tcp: false, sourcePort: 2000,
        destPort: 443, payload: [1, 2, 3]);
    final okay = PcapInspector.parseBytes(
        _pcap(List.filled(161, packet)));
    expect(okay.packetCount, 161);
    expect(okay.truncated, isTrue);
    expect(okay.observations.length, 160);
    expect(
      () => PcapInspector.parseBytes(_pcap(List.filled(2501, packet))),
      throwsFormatException,
    );
  });
}
