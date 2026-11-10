/// Restricted, user-mediated Android handoff for Chappy Hub Mobile only.
///
/// This policy deliberately does not expose accessibility controls, ChatGPT
/// output scraping, or a generic arbitrary-app automation channel.
class MiniAppHandoffPolicy {
  static const allowedAppId = 'local.chappy.hubmobile';
  static const maxTextLength = 5000;

  static bool isAllowed(String appId) => appId == allowedAppId;

  static String requirePrompt(Object? input) {
    if (input is! String || input.trim().isEmpty || input.length > maxTextLength) {
      throw const FormatException('指示文は1〜5000文字で指定してください');
    }
    return input;
  }
}
