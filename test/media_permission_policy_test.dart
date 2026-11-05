import 'package:chappy_player/core/media_permission_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only declared media resources can be requested', () {
    expect(canRequestChappyMedia([], ['camera']), isFalse);
    expect(canRequestChappyMedia(['camera'], ['camera']), isTrue);
    expect(canRequestChappyMedia(['camera'], ['microphone']), isFalse);
    expect(canRequestChappyMedia(
        ['camera', 'microphone'], ['camera', 'microphone']), isTrue);
    expect(canRequestChappyMedia(
        ['camera', 'microphone'], ['camera', 'location']), isFalse);
    expect(canRequestChappyMedia(['camera'], []), isFalse);
    expect(canRequestChappyMedia(
        ['camera', 'microphone'], ['microphone', 'microphone']), isFalse);
  });
}
