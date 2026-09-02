import 'package:flutter_test/flutter_test.dart';

import 'package:hanbut/game_rules.dart';
import 'package:hanbut/nickname_policy.dart';

void main() {
  group('GameRules', () {
    test('고스테이지에서도 노드 수가 안전한 상한을 넘지 않는다', () {
      expect(GameRules.safeNodeCount(1), 2);
      expect(GameRules.safeNodeCount(100), GameRules.maxSafeNodes);
    });

    test('허용 가능한 최대 점수는 스테이지와 함께 증가한다', () {
      expect(GameRules.maximumScoreThroughStage(0), 0);
      expect(
        GameRules.maximumScoreThroughStage(10),
        greaterThan(GameRules.maximumScoreThroughStage(9)),
      );
    });
  });

  group('NicknamePolicy', () {
    test('공백을 정규화한다', () {
      final NicknameValidation result = NicknamePolicy.validate(' 구름   친구 ');
      expect(result.isValid, isTrue);
      expect(result.value, '구름 친구');
    });

    test('URL과 부적절한 표현을 거부한다', () {
      expect(NicknamePolicy.validate('www.example.com').isValid, isFalse);
      expect(NicknamePolicy.validate('fuck').isValid, isFalse);
    });
  });
}
