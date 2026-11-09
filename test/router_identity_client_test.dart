import 'package:chappy_player/core/router_identity_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.chappy.player/network_lab');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return <String, dynamic>{
        'gatewayIpv4': '192.168.11.1',
        'source': 'android_wifi_default_route',
        'evidence': 'upnp_self_report',
        'manufacturer': 'BUFFALO INC.',
        'modelName': 'AirStation',
        'modelNumber': 'WSR-TEST',
        'friendlyName': 'Home router',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('one-shot probe has no arguments and treats UPnP model as a hint',
      () async {
    const client = RouterIdentityClient(channel: channel);
    final result = await client.probe();
    expect(calls, ['routerIdentityProbe']);
    expect(result.gatewayIpv4, '192.168.11.1');
    expect(result.hasAdvertisedIdentity, isTrue);
    expect(result.manufacturer, 'BUFFALO INC.');
    expect(result.modelNumber, 'WSR-TEST');
  });

  test('gateway only is valid and never guesses a router brand', () {
    final result = RouterIdentitySnapshot.fromWire({
      'gatewayIpv4': '10.0.0.1',
      'source': 'android_wifi_default_route',
      'evidence': 'gateway_only',
      'manufacturer': '',
      'modelName': '',
      'modelNumber': '',
      'friendlyName': '',
    });
    expect(result.hasAdvertisedIdentity, isFalse);
    expect(result.modelName, isNull);
    expect(result.manufacturer, isNull);
  });

  test('rejects public or forged gateway and unrecognized evidence', () {
    final wire = {
      'gatewayIpv4': '8.8.8.8',
      'source': 'android_wifi_default_route',
      'evidence': 'gateway_only',
      'manufacturer': '',
      'modelName': '',
      'modelNumber': '',
      'friendlyName': '',
    };
    expect(() => RouterIdentitySnapshot.fromWire(wire), throwsFormatException);
    expect(
      () => RouterIdentitySnapshot.fromWire({
        ...wire,
        'gatewayIpv4': '192.168.0.1',
        'source': 'unknown_api',
      }),
      throwsFormatException,
    );
    expect(
      () => RouterIdentitySnapshot.fromWire({
        ...wire,
        'gatewayIpv4': '192.168.0.1',
        'evidence': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      () => RouterIdentitySnapshot.fromWire({
        ...wire,
        'gatewayIpv4': '192.168.0.1',
        'manufacturer': 'BUFFALO',
      }),
      throwsFormatException,
    );
  });

  test('restricts untrusted UPnP labels and private gateway format', () {
    expect(RouterIdentitySnapshot.isPrivateIpv4('192.168.11.1'), isTrue);
    expect(RouterIdentitySnapshot.isPrivateIpv4('172.31.0.1'), isTrue);
    expect(RouterIdentitySnapshot.isPrivateIpv4('127.0.0.1'), isFalse);
    expect(RouterIdentitySnapshot.isPrivateIpv4('169.254.1.1'), isFalse);
    expect(RouterIdentitySnapshot.isPrivateIpv4('1.1.1.1'), isFalse);
    expect(RouterIdentitySnapshot.isPrivateIpv4('192.168.001.1'), isFalse);
    final result = RouterIdentitySnapshot.fromWire({
      'gatewayIpv4': '192.168.11.1',
      'source': 'android_wifi_default_route',
      'evidence': 'upnp_self_report',
      'manufacturer': '<script>',
      'modelName': 'https://invalid.example',
      'modelNumber': 'WSR-LAB-01',
      'friendlyName': 'Test\nInjected',
    });
    expect(result.manufacturer, isNull);
    expect(result.modelName, isNull);
    expect(result.modelNumber, 'WSR-LAB-01');
    expect(result.friendlyName, isNull);
  });
}
