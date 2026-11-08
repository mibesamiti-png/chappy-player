import 'dart:convert';
import 'dart:io';

import 'package:chappy_player/core/pc_link_preview_session.dart';
import 'package:flutter_test/flutter_test.dart';

const now = 1800000000;
const expiry = now + 60;

PcLinkPreviewSession fresh() =>
    PcLinkPreviewSession(nowEpochSeconds: now, expiresAt: expiry);

PcLinkPreviewSession verified() {
  final s = fresh();
  expect(s.verify(identityVerified: true, nowEpochSeconds: now), isTrue);
  return s;
}

PcLinkPreviewSession active() {
  final s = verified();
  expect(s.requestReadOnly(capability: PcLinkPreviewSession.readStatus,
      nowEpochSeconds: now), isTrue);
  expect(s.consent(side: 'pc', approved: true, nowEpochSeconds: now), isTrue);
  expect(s.consent(side: 'android', approved: true, nowEpochSeconds: now),
      isTrue);
  return s;
}

void main() {
  final fixture = jsonDecode(
      File('docs/pc-link-session-preview-v1.json').readAsStringSync())
      as Map<String, dynamic>;

  test('Dart preview constants match the cross-language fixture', () {
    expect(fixture['schemaVersion'], 1);
    expect(PcLinkPreviewSession.protocol, fixture['protocol']);
    expect(PcLinkPreviewSession.readStatus, fixture['capability']);
    expect(PcLinkPreviewSession.maxLifetimeSeconds,
        fixture['maxLifetimeSeconds']);
    expect(PcLinkPreviewPhase.values.map((p) => p.wire).toList(),
        fixture['phases']);
  });

  test('QR identity confirmation itself grants zero permissions', () {
    final s = verified();
    expect(s.phase(now), PcLinkPreviewPhase.verified);
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isFalse);
    expect(s.allows(capability: 'pc.control', nowEpochSeconds: now), isFalse);
  });

  test('only the PC and Android explicit consents enable read-only status',
      () {
    final s = verified();
    expect(s.requestReadOnly(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isTrue);
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isFalse);
    expect(s.consent(side: 'android', approved: true, nowEpochSeconds: now),
        isTrue);
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isFalse);
    expect(s.consent(side: 'pc', approved: true, nowEpochSeconds: now), isTrue);
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isTrue);
    expect(s.allows(capability: 'pc.files.read', nowEpochSeconds: now), isFalse);
  });

  test('expiry and invalid setup fail closed', () {
    for (final invalid in [now, now - 1, now + 121]) {
      expect(() => PcLinkPreviewSession(
          nowEpochSeconds: now, expiresAt: invalid), throwsArgumentError);
    }
    final s = active();
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: expiry), isFalse);
    expect(s.phase(expiry), PcLinkPreviewPhase.closed);
  });

  test('denial, replay, wrong capability and cancel revoke authority', () {
    final denied = verified();
    denied.requestReadOnly(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now);
    expect(denied.consent(side: 'pc', approved: false, nowEpochSeconds: now),
        isFalse);
    expect(denied.phase(now), PcLinkPreviewPhase.closed);
    final duplicate = verified();
    duplicate.requestReadOnly(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now);
    expect(duplicate.consent(side: 'pc', approved: true, nowEpochSeconds: now),
        isTrue);
    expect(duplicate.consent(side: 'pc', approved: true, nowEpochSeconds: now),
        isFalse);
    expect(duplicate.consent(
        side: 'android', approved: true, nowEpochSeconds: now), isFalse);
    final badScope = verified();
    expect(badScope.requestReadOnly(capability: 'pc.control',
        nowEpochSeconds: now), isFalse);
    expect(badScope.phase(now), PcLinkPreviewPhase.closed);
    final cancelled = active();
    cancelled.cancel();
    expect(cancelled.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isFalse);
  });

  test('strict JSON fixtures and replay protection have Python parity', () {
    final s = active();
    final request = (fixture['request'] as Map).cast<String, dynamic>();
    final response = (fixture['response'] as Map).cast<String, dynamic>();
    expect(s.acceptFixtureRequest(message: request, nowEpochSeconds: now),
        response);
    expect(PcLinkPreviewSession.validateFixtureResponse(
        message: response, sequence: 1), isTrue);
    expect(s.acceptFixtureRequest(message: request, nowEpochSeconds: now),
        isNull);
    expect(s.allows(capability: PcLinkPreviewSession.readStatus,
        nowEpochSeconds: now), isFalse);
    final invalid = Map<String, dynamic>.of(response)..['online'] = 1;
    expect(PcLinkPreviewSession.validateFixtureResponse(
        message: invalid, sequence: 1), isFalse);
    invalid['online'] = true;
    invalid['privateKey'] = 'not allowed';
    expect(PcLinkPreviewSession.validateFixtureResponse(
        message: invalid, sequence: 1), isFalse);
  });

  test('actual Dart HTTP client exchanges strict fixture with Python loopback',
      () async {
    // Test-only Python server binds 127.0.0.1, handles exactly one request;
    // this cannot authenticate or obtain any state from a real Windows PC.
    final python = Platform.isWindows ? 'python' : 'python3';
    final child = await Process.start(
        python, ['tools/pc_link_r4b_loopback_fixture.py']);
    try {
      final portLine = await child.stdout
          .transform(utf8.decoder).transform(const LineSplitter())
          .first.timeout(const Duration(seconds: 10));
      final port = int.parse(portLine);
      expect(port, inInclusiveRange(1, 65535));
      final client = HttpClient();
      try {
        final uri = Uri(scheme: 'http', host: '127.0.0.1',
            port: port, path: '/fixture');
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        final bodyBytes = utf8.encode(jsonEncode(fixture['request']));
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);
        final reply = await req.close().timeout(const Duration(seconds: 10));
        expect(reply.statusCode, HttpStatus.ok);
        final body = await utf8.decoder.bind(reply).join();
        final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
        expect(decoded, fixture['response']);
        expect(PcLinkPreviewSession.validateFixtureResponse(
            message: decoded, sequence: 1), isTrue);
      } finally {
        client.close(force: true);
      }
      expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
    } finally {
      child.kill();
    }
  });
}
