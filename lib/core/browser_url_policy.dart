/// Network R7 trusted-host browser policy. Never imported into .chappy JS.
/// R7 deliberately accepts public HTTPS hostnames only; no private LAN or
/// arbitrary schemes. It is a URL preflight, NOT a DNS-rebinding firewall.
class BrowserUrlPolicy {
  static const int maxLength = 2048;

  /// For a user-typed address, assume HTTPS only when no scheme was entered.
  static Uri fromInput(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > maxLength ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      throw const FormatException('URLを確認してください');
    }
    final absolute = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value);
    return fromNavigation(absolute ? value : 'https://' + value);
  }

  /// Reject a blocked navigation instead of converting it to a different URL.
  static Uri fromNavigation(String value) {
    if (value.isEmpty || value.length > maxLength ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      throw const FormatException('無効なURLです');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasPort && uri.port != 443) {
      throw const FormatException('公開HTTPSサイトのみ対応します');
    }
    final host = uri.host.toLowerCase();
    if (host.endsWith('.') || host.contains(':') ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.home') ||
        host.endsWith('.internal') ||
        host.endsWith('.test') ||
        host.endsWith('.invalid') ||
        host.endsWith('.example') ||
        RegExp(r'^[0-9.]+$').hasMatch(host)) {
      throw const FormatException('端末内・LANアドレスはブラウザで開けません');
    }
    final labels = host.split('.');
    final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    if (labels.length < 2 || labels.any((part) => !label.hasMatch(part)) ||
        labels.last.length < 2 || RegExp(r'^[0-9]+$').hasMatch(labels.last)) {
      throw const FormatException('有効な公開DNSホスト名を指定してください');
    }
    return uri;
  }

  static bool allowsNavigation(String url) {
    try {
      fromNavigation(url);
      return true;
    } on FormatException {
      return false;
    }
  }
}
