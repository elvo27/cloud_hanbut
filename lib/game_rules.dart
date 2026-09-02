import 'dart:math';

class GameRules {
  const GameRules._();

  static const int maxSafeNodes = 28;
  static const int maxAcceptedStage = 200;

  static int safeNodeCount(int stage) => min(max(stage, 1) + 1, maxSafeNodes);

  static int stageTimeLimit(int stage) {
    final int safeCount = safeNodeCount(stage);
    if (stage >= 40) {
      return 20;
    }
    if (stage >= 30) {
      return 25;
    }
    return (8 + safeCount * 3).clamp(8, 30);
  }

  static int maximumStageScore(int stage) =>
      max(stage, 1) * 100 + stageTimeLimit(stage) * 5;

  /// A deliberately generous upper bound used for rejecting obviously forged
  /// leaderboard submissions while keeping older app versions compatible.
  static int maximumScoreThroughStage(int lastStage) {
    final int cappedStage = lastStage.clamp(0, maxAcceptedStage);
    int total = 0;
    for (int stage = 1; stage <= cappedStage; stage += 1) {
      total += maximumStageScore(stage);
    }
    return total;
  }
}
