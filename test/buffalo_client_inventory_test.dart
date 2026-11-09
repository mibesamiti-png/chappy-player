import 'package:chappy_player/core/buffalo_client_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads owner-copied BUFFALO rows without device-side pairing', () {
    final devices = BuffaloClientInventoryParser.parse(
      'IPアドレス MACアドレス\n'
      '192.168.11.10, AA:BB:CC:DD:EE:01, MyPhone\n'
      '192.168.11.12, AA-BB-CC-DD-EE-02, UnknownDevice\n'
      'AA:BB:CC:DD:EE:03\n'
      '192.168.11.13\n',
    );
    expect(devices, hasLength(4));
    expect(devices[0].hostname, 'MyPhone');
    expect(devices[0].ip, '192.168.11.10');
    expect(devices[0].mac, 'AA:BB:CC:DD:EE:01');
    expect(devices[1].hostname, 'UnknownDevice');
    expect(devices[1].mac, 'AA:BB:CC:DD:EE:02');
    expect(devices[2].ip, isNull);
    expect(devices[2].mac, 'AA:BB:CC:DD:EE:03');
    expect(devices[3].ip, '192.168.11.13');
    expect(devices[3].mac, isNull);
  });

  test('does not treat duplicate rows or public IP addresses as LAN clients',
      () {
    final devices = BuffaloClientInventoryParser.parse(
      '192.168.11.10\tAA:BB:CC:DD:EE:01\tOwner\n'
      '192.168.11.10\tAA:BB:CC:DD:EE:01\tDuplicate\n'
      '8.8.8.8\n'
      '127.0.0.1\n'
      '192.168.11.11\n'
      '192.168.11.10 192.168.11.12\n',
    );
    expect(devices, hasLength(2));
    expect(devices[0].hostname, 'Owner');
    expect(devices[1].ip, '192.168.11.11');
  });

  test('rejects large or unsafe pasted lists', () {
    expect(
      () => BuffaloClientInventoryParser.parse(
        List.filled(257, '192.168.11.20').join('\n'),
      ),
      throwsFormatException,
    );
    expect(
      () => BuffaloClientInventoryParser.parse(List.filled(32769, 'a').join()),
      throwsFormatException,
    );
    expect(
      BuffaloClientInventoryParser.parse(
        '192.168.11.50, AA:BB:CC:DD:EE:08, <script>alert(1)</script>',
      ).single.hostname,
      isNull,
    );
    expect(
      BuffaloClientInventoryParser.normalizeMac('AABBCCDDEEAA'),
      'AA:BB:CC:DD:EE:AA',
    );
    expect(
      BuffaloClientInventoryParser.parse('router password=secret'),
      isEmpty,
    );
  });

  test('caps at 128 devices and never infers unknown means unauthorized',
      () {
    final rows = List.generate(129, (i) =>
        '192.168.11.${i + 10}');
    expect(
      () => BuffaloClientInventoryParser.parse(rows.join('\n')),
      throwsFormatException,
    );
    expect(
      BuffaloClientInventoryParser.parse('10.1.2.3').single.mac,
      isNull,
    );
  });
}
