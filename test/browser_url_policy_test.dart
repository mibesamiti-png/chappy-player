import 'package:chappy_player/core/browser_url_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed public hostnames use HTTPS, with no hidden search provider', () {
    expect(BrowserUrlPolicy.fromInput('example.com').toString(),
        'https://example.com');
    expect(BrowserUrlPolicy.fromInput(' https://example.com/path?q=1 ').host,
        'example.com');
    expect(BrowserUrlPolicy.fromNavigation('https://example.com:443/').scheme,
        'https');
    expect(BrowserUrlPolicy.allowsNavigation('https://www.wikipedia.org/'),
        isTrue);
  });

  test('unsafe schemes, private network hosts and credential URL are blocked',
      () {
    for (final input in [
      'http://example.com', 'javascript:alert(1)', 'data:text/html,a',
      'file:///etc/hosts', 'content://docs/a', 'intent://go',
      'ftp://example.com', 'https://localhost/',
      'https://box.local/', 'https://device.lan/',
      'https://service.internal/', 'https://127.0.0.1/',
      'https://192.168.1.1/', 'https://[::1]/',
      'https://user:secret@example.com/', 'https://example.com:8443/',
      'https://example/', 'https://bad_host.example.com/',
      'https://example.com/a\nb', 'https://example.com\\@evil.invalid',
    ]) {
      expect(() => BrowserUrlPolicy.fromInput(input),
          throwsFormatException, reason: input);
      expect(BrowserUrlPolicy.allowsNavigation(input), isFalse,
          reason: input);
    }
  });

  test('navigation never auto-upgrades HTTP and disallows empty/oversize', () {
    expect(BrowserUrlPolicy.allowsNavigation('example.com'), isFalse);
    expect(BrowserUrlPolicy.allowsNavigation('http://example.com/'), isFalse);
    expect(() => BrowserUrlPolicy.fromInput(''), throwsFormatException);
    expect(() => BrowserUrlPolicy.fromInput('e' * 2049),
        throwsFormatException);
    expect(() => BrowserUrlPolicy.fromInput('https://example.com/this path'),
        throwsFormatException);
  });
}
