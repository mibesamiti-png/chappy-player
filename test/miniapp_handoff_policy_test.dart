import 'package:chappy_player/core/miniapp_handoff_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MiniAppHandoffPolicy', () {
    test('only authorizes the dedicated Hub Mobile app ID', () {
      expect(MiniAppHandoffPolicy.isAllowed('local.chappy.hubmobile'), isTrue);
      expect(MiniAppHandoffPolicy.isAllowed('local.chappy.memo'), isFalse);
      expect(MiniAppHandoffPolicy.isAllowed('local.chappy.hubmobile.evil'), isFalse);
    });
    test('limits text and never changes the prompt', () {
      expect(MiniAppHandoffPolicy.requirePrompt('  テスト\n'), '  テスト\n');
      expect(MiniAppHandoffPolicy.requirePrompt('x' * 5000), hasLength(5000));
      expect(() => MiniAppHandoffPolicy.requirePrompt(''), throwsFormatException);
      expect(() => MiniAppHandoffPolicy.requirePrompt('  '), throwsFormatException);
      expect(() => MiniAppHandoffPolicy.requirePrompt('x' * 5001), throwsFormatException);
      expect(() => MiniAppHandoffPolicy.requirePrompt(12), throwsFormatException);
    });
  });
}
