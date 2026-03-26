import 'package:supabase_flutter/supabase_flutter.dart';

enum RemoteHighScoreSort { score, latest, oldest, topStage }

class RemoteHighScoreEntry {
  const RemoteHighScoreEntry({
    required this.nickname,
    required this.score,
    required this.lastStage,
    required this.playedAt,
  });

  final String nickname;
  final int score;
  final int lastStage;
  final DateTime playedAt;

  factory RemoteHighScoreEntry.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, int fallback) {
      if (value is int) {
        return value;
      }
      if (value is double) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return RemoteHighScoreEntry(
      nickname: (json['nickname'] as String? ?? '').trim(),
      score: parseInt(json['score'], 0),
      lastStage: parseInt(json['last_stage'], 0),
      playedAt: parseDate(json['played_at']),
    );
  }
}

class GameHighScoreRepository {
  Future<void> submitBestScore({
    required String gameName,
    required String nickname,
    required int score,
    int? lastStage,
    DateTime? playedAt,
  }) async {
    await Supabase.instance.client.rpc(
      'submit_game_high_score',
      params: <String, dynamic>{
        'p_game_name': gameName.trim(),
        'p_nickname': nickname.trim(),
        'p_score': score,
        'p_last_stage': lastStage,
        'p_played_at': playedAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<List<RemoteHighScoreEntry>> fetchHighScores({
    required String gameName,
    int limit = 50,
    RemoteHighScoreSort sort = RemoteHighScoreSort.score,
  }) async {
    final baseQuery = Supabase.instance.client
        .from('game_high_scores')
        .select('nickname, score, last_stage, played_at')
        .eq('game_name', gameName.trim());

    final List<dynamic> rows;
    switch (sort) {
      case RemoteHighScoreSort.score:
        rows = await baseQuery
            .order('score', ascending: false)
            .order('last_stage', ascending: false)
            .order('played_at', ascending: false)
            .limit(limit);
      case RemoteHighScoreSort.latest:
        rows = await baseQuery
            .order('played_at', ascending: false)
            .order('score', ascending: false)
            .order('last_stage', ascending: false)
            .limit(limit);
      case RemoteHighScoreSort.oldest:
        rows = await baseQuery
            .order('played_at', ascending: true)
            .order('score', ascending: false)
            .order('last_stage', ascending: false)
            .limit(limit);
      case RemoteHighScoreSort.topStage:
        rows = await baseQuery
            .order('last_stage', ascending: false)
            .order('score', ascending: false)
            .order('played_at', ascending: false)
            .limit(limit);
    }

    return rows
        .map(
          (dynamic row) =>
              RemoteHighScoreEntry.fromJson(row as Map<String, dynamic>),
        )
        .where((RemoteHighScoreEntry entry) => entry.nickname.isNotEmpty)
        .toList(growable: false);
  }
}
