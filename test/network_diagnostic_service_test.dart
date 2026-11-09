import 'dart:async';

import 'package:chappy_player/core/network_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full one-shot route reports only counts/bool/HTTP code', () async {
    final calls = <String>[];
    final service = NetworkDiagnosticService(
      interfaceProbe: () async { calls.add('interface'); return 2; },
      dnsProbe: () async { calls.add('dns'); return true; },
      httpsProbe: () async { calls.add('https'); return 200; },
    );
    final snapshot = await service.run();
    expect(calls, ['interface', 'dns', 'https']);
    expect(snapshot.interfaceCount, 2);
    expect(snapshot.dnsResolved, true);
    expect(snapshot.httpsStatus, 200);
    expect(snapshot.stoppedAt, isNull);
    expect(() => service.run(), throwsStateError);
  });

  test('no interface never makes DNS/HTTPS network requests', () async {
    final service = NetworkDiagnosticService(
      interfaceProbe: () async => 0,
      dnsProbe: () async => throw StateError('must not run DNS'),
      httpsProbe: () async => throw StateError('must not run HTTPS'),
    );
    final s = await service.run();
    expect(s.interfaceCount, 0);
    expect(s.stoppedAt, 'no_interface');
    expect(s.httpsStatus, isNull);
  });

  test('DNS rejection blocks HTTP with no private error disclosure', () async {
    final service = NetworkDiagnosticService(
      interfaceProbe: () async => 1,
      dnsProbe: () async => throw StateError('private IP secret'),
      httpsProbe: () async => throw StateError('must not run'),
    );
    final s = await service.run();
    expect(s.dnsResolved, isFalse);
    expect(s.stoppedAt, 'dns');
    expect(s.httpsStatus, isNull);
    expect(s.toString(), isNot(contains('private IP secret')));
  });

  test('HTTPS exception is a safe stage, not an error stack', () async {
    final service = NetworkDiagnosticService(
      interfaceProbe: () async => 1,
      dnsProbe: () async => true,
      httpsProbe: () async => throw SocketExceptionForTest(),
    );
    final s = await service.run();
    expect(s.stoppedAt, 'https');
    expect(s.dnsResolved, isTrue);
    expect(s.httpsStatus, isNull);
  });

  test('cancel before run and during run closes pending result', () async {
    final first = NetworkDiagnosticService();
    first.cancel();
    expect(() => first.run(), throwsStateError);
    final pending = Completer<bool>();
    final service = NetworkDiagnosticService(
      interfaceProbe: () async => 1,
      dnsProbe: () => pending.future,
      httpsProbe: () async => throw StateError('must not run'),
    );
    final future = service.run();
    await Future<void>.delayed(Duration.zero);
    service.cancel();
    pending.complete(true);
    final s = await future;
    expect(s.stoppedAt, 'cancelled');
    expect(s.httpsStatus, isNull);
  });
}

class SocketExceptionForTest implements Exception {}
