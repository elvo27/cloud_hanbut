import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hanbut/game_high_score_repository.dart';
import 'package:hanbut/supabase_project.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseProject.url,
    anonKey: SupabaseProject.publishableKey,
  );
  runApp(const HanbutApp());
}

class HanbutApp extends StatelessWidget {
  const HanbutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '구름친구맺기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _historyStorageKey = 'cloud_connect_history';
  static const String _nicknameStorageKey = 'cloud_connect_nickname';
  static const int _maxHistoryLength = 100;
  static const String _appVersion = '1.0.4';

  final GameHighScoreRepository _highScoreRepository =
      GameHighScoreRepository();
  List<GameResult> _history = <GameResult>[];
  bool _isLoadingHistory = true;
  String _savedNickname = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList(_historyStorageKey);
    final String savedNickname =
        prefs.getString(_nicknameStorageKey)?.trim() ?? '';

    if (!mounted) {
      return;
    }

    if (stored == null) {
      setState(() {
        _savedNickname = savedNickname;
        _isLoadingHistory = false;
      });
      return;
    }

    final List<GameResult> parsed = <GameResult>[];
    for (final String entry in stored) {
      try {
        final Map<String, dynamic> data =
            jsonDecode(entry) as Map<String, dynamic>;
        parsed.add(GameResult.fromJson(data));
      } catch (_) {
        // Ignore malformed entries.
      }
    }

    parsed.sort(
      (GameResult a, GameResult b) => a.finishedAt.compareTo(b.finishedAt),
    );

    setState(() {
      _history = parsed;
      _savedNickname = savedNickname;
      _isLoadingHistory = false;
    });
  }

  Future<void> _persistHistory(List<GameResult> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> encoded = entries
        .map((GameResult e) => jsonEncode(e.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_historyStorageKey, encoded);
  }

  Future<void> _persistNickname(String nickname) async {
    final String normalized = nickname.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameStorageKey, normalized);

    if (!mounted) {
      return;
    }

    setState(() {
      _savedNickname = normalized;
    });
  }

  Future<void> _addResult(GameResult result) async {
    final List<GameResult> updated = List<GameResult>.from(_history)
      ..add(result);
    final List<GameResult> trimmed = updated.length > _maxHistoryLength
        ? updated.sublist(updated.length - _maxHistoryLength)
        : updated;

    setState(() {
      _history = trimmed;
    });

    await _persistHistory(trimmed);
  }

  Future<void> _startGame(BuildContext context) async {
    final GameResult? result = await Navigator.of(context).push<GameResult>(
      MaterialPageRoute<GameResult>(
        builder: (BuildContext context) => const CloudConnectPage(),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final int? previousBestScore = _history.isEmpty
        ? null
        : _history.map((GameResult entry) => entry.score).reduce(max);
    final int? previousBestStage = _history.isEmpty
        ? null
        : _history.map((GameResult entry) => entry.lastStage).reduce(max);

    await _addResult(result);
    await _maybeSubmitBestScore(
      result,
      previousBestScore: previousBestScore,
      previousBestStage: previousBestStage,
    );
  }

  Future<void> _maybeSubmitBestScore(
    GameResult result, {
    required int? previousBestScore,
    required int? previousBestStage,
  }) async {
    final _BestRecordUpdateKind? updateKind = _getBestRecordUpdateKind(
      result,
      previousBestScore: previousBestScore,
      previousBestStage: previousBestStage,
    );

    if (updateKind == null || !mounted) {
      return;
    }

    final String? nickname = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return _NicknamePromptDialog(
          initialNickname: _savedNickname,
          result: result,
          updateKind: updateKind,
        );
      },
    );

    if (!mounted || nickname == null) {
      return;
    }

    final String normalizedNickname = nickname.trim();
    if (normalizedNickname.isEmpty) {
      return;
    }

    await _persistNickname(normalizedNickname);

    try {
      await _highScoreRepository.submitBestScore(
        gameName: SupabaseProject.cloudConnectGameName,
        nickname: normalizedNickname,
        score: result.score,
        lastStage: result.lastStage,
        playedAt: result.finishedAt,
      );

      if (!mounted) {
        return;
      }

      _showSnackBar('${updateKind.savedMessage} 닉네임과 함께 저장됐어요.');
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('기록 저장 실패: ${error.message}', isError: true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('네트워크 문제로 기록 저장에 실패했어요.', isError: true);
    }
  }

  _BestRecordUpdateKind? _getBestRecordUpdateKind(
    GameResult result, {
    required int? previousBestScore,
    required int? previousBestStage,
  }) {
    if (previousBestScore == null || previousBestStage == null) {
      return _BestRecordUpdateKind.firstRecord;
    }

    final bool scoreUpdated = result.score > previousBestScore;
    final bool stageUpdated = result.lastStage > previousBestStage;

    if (scoreUpdated && stageUpdated) {
      return _BestRecordUpdateKind.scoreAndStage;
    }
    if (scoreUpdated) {
      return _BestRecordUpdateKind.scoreOnly;
    }
    if (stageUpdated) {
      return _BestRecordUpdateKind.stageOnly;
    }
    return null;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  void _showMyHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) {
        final List<GameResult> entries = List<GameResult>.from(
          _history.reversed,
        );
        final double maxHeight = min(
          MediaQuery.of(context).size.height * 0.7,
          480,
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '내 기록',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '닫기',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '아직 저장된 기록이 없어요. 게임을 플레이해보세요!',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  SizedBox(
                    height: maxHeight,
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final GameResult entry = entries[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.blueGrey.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: <Widget>[
                              _StageBadge(stage: entry.lastStage),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Stage ${entry.lastStage}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${entry.score}점 · ${_formatTimestamp(entry.finishedAt)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.blueGrey.shade600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOtherPlayersHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) {
        final double maxHeight = min(
          MediaQuery.of(context).size.height * 0.7,
          520,
        );
        RemoteHighScoreSort currentSort = RemoteHighScoreSort.score;
        Future<List<RemoteHighScoreEntry>> future = _highScoreRepository
            .fetchHighScores(
              gameName: SupabaseProject.cloudConnectGameName,
              sort: currentSort,
            );

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Future<void> refreshScores(RemoteHighScoreSort nextSort) async {
              setModalState(() {
                currentSort = nextSort;
                future = _highScoreRepository.fetchHighScores(
                  gameName: SupabaseProject.cloudConnectGameName,
                  sort: currentSort,
                );
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '다른 사람 기록',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: '닫기',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: RemoteHighScoreSort.values.map((
                        RemoteHighScoreSort sort,
                      ) {
                        return ChoiceChip(
                          label: Text(_sortLabel(sort)),
                          selected: currentSort == sort,
                          onSelected: (bool selected) {
                            if (!selected || currentSort == sort) {
                              return;
                            }
                            refreshScores(sort);
                          },
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<List<RemoteHighScoreEntry>>(
                      future: future,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<List<RemoteHighScoreEntry>> snapshot,
                          ) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 24,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '다른 사람 기록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        final List<RemoteHighScoreEntry> entries =
                            snapshot.data ?? const <RemoteHighScoreEntry>[];

                        if (entries.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 24,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.lightBlue.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '아직 등록된 다른 사람 기록이 없어요.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return SizedBox(
                          height: maxHeight,
                          child: ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final RemoteHighScoreEntry entry = entries[index];
                              final int rank = index + 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.blueGrey.withValues(alpha: 0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: <Widget>[
                                    _buildOtherScoreBadge(
                                      context,
                                      sort: currentSort,
                                      rank: rank,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            entry.nickname,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Stage ${entry.lastStage} · ${_formatTimestamp(entry.playedAt)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.blueGrey.shade600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${entry.score}점',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.blueGrey.shade800,
                                          ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _sortLabel(RemoteHighScoreSort sort) {
    switch (sort) {
      case RemoteHighScoreSort.score:
        return '점수순';
      case RemoteHighScoreSort.latest:
        return '최신순';
      case RemoteHighScoreSort.oldest:
        return '오래된순';
      case RemoteHighScoreSort.topStage:
        return '최고스테이지 순';
    }
  }

  Widget _buildOtherScoreBadge(
    BuildContext context, {
    required RemoteHighScoreSort sort,
    required int rank,
  }) {
    if (sort == RemoteHighScoreSort.score) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: rank <= 3
            ? Colors.amber.shade100
            : Colors.lightBlue.shade100,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.lightBlue.shade100,
      child: Icon(
        sort == RemoteHighScoreSort.latest
            ? Icons.schedule_rounded
            : sort == RemoteHighScoreSort.oldest
                ? Icons.history_rounded
                : Icons.flag_rounded,
        color: Colors.blueGrey.shade800,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final DateTime local = timestamp.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}.${twoDigits(local.month)}.${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final GameResult? latestResult =
        _history.isNotEmpty ? _history.last : null;
    final GameResult? bestResult = _history.isNotEmpty
        ? _history.reduce(
            (GameResult a, GameResult b) =>
                a.score >= b.score ? a : b,
          )
        : null;
    final bool latestIsBest =
        latestResult != null && identical(bestResult, latestResult);

    return Scaffold(
      backgroundColor: Colors.lightBlue.shade50,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double horizontalPadding = 28;
            const double topPadding = 32;
            final double bottomPadding =
                MediaQuery.of(context).padding.bottom + 36;
            final double minHeight = max(
              constraints.maxHeight - (topPadding + bottomPadding),
              0,
            );

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                bottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      LayoutBuilder(
                        builder:
                            (
                              BuildContext context,
                              BoxConstraints innerConstraints,
                            ) {
                              final double cardWidth = min(
                                MediaQuery.of(context).size.width * 0.52,
                                210,
                              );

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(32),
                                child: Image.asset(
                                  'assets/images/clo_card.png',
                                  width: cardWidth,
                                ),
                              );
                            },
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '구름 친구 맺기',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey.shade800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '비구름을 피해 모든 구름을 한 번에 이어보세요!',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.blueGrey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _startGame(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '게임 시작',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _showMyHistorySheet,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.lightBlue.shade200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '내 기록 보기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _showOtherPlayersHistorySheet,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.lightBlue.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.7),
                          ),
                          child: const Text(
                            '다른 사람 기록 보기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_isLoadingHistory)
                        const Padding(
                          padding: EdgeInsets.only(top: 32),
                          child: CircularProgressIndicator(),
                        )
                      else if (latestResult != null) ...<Widget>[
                        const SizedBox(height: 24),
                        _RecordCard(
                          title: '직전 기록',
                          stageLabel: 'Stage ${latestResult.lastStage}',
                          scoreLabel: '${latestResult.score}점',
                          timestamp: _formatTimestamp(latestResult.finishedAt),
                          highlight: latestIsBest,
                        ),
                        if (bestResult != null && !latestIsBest)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _RecordCard(
                              title: '최고 기록',
                              stageLabel: 'Stage ${bestResult.lastStage}',
                              scoreLabel: '${bestResult.score}점',
                              timestamp: _formatTimestamp(bestResult.finishedAt),
                              highlight: true,
                            ),
                          ),
                      ],
                      const SizedBox(height: 32),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'thanks to Lovy',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.lightBlue.shade300,
                                      fontStyle: FontStyle.italic,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.favorite,
                                size: 20,
                                color: Colors.pinkAccent.shade200,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'v$_appVersion',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.blueGrey.shade400,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class GameResult {
  GameResult({
    required this.lastStage,
    required this.score,
    DateTime? finishedAt,
  }) : finishedAt = finishedAt ?? DateTime.now();

  final int lastStage;
  final int score;
  final DateTime finishedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lastStage': lastStage,
    'score': score,
    'finishedAt': finishedAt.toIso8601String(),
  };

  factory GameResult.fromJson(Map<String, dynamic> json) {
    final dynamic stageValue = json['lastStage'];
    final dynamic scoreValue = json['score'];
    final dynamic finishedValue = json['finishedAt'];

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
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return GameResult(
      lastStage: parseInt(stageValue, 0),
      score: parseInt(scoreValue, 0),
      finishedAt: parseDate(finishedValue),
    );
  }
}

enum _BestRecordUpdateKind {
  firstRecord,
  scoreOnly,
  stageOnly,
  scoreAndStage;

  String get title {
    switch (this) {
      case _BestRecordUpdateKind.firstRecord:
        return '첫 기록 달성';
      case _BestRecordUpdateKind.scoreOnly:
        return '최고 점수 갱신';
      case _BestRecordUpdateKind.stageOnly:
        return '최고 스테이지 갱신';
      case _BestRecordUpdateKind.scoreAndStage:
        return '점수와 스테이지 모두 갱신';
    }
  }

  String get promptMessage {
    switch (this) {
      case _BestRecordUpdateKind.firstRecord:
        return '첫 기록이에요. 닉네임과 함께 남겨둘까요?';
      case _BestRecordUpdateKind.scoreOnly:
        return '최고 점수를 새로 썼어요. 닉네임과 함께 기록해보세요.';
      case _BestRecordUpdateKind.stageOnly:
        return '최고 스테이지를 돌파했어요. 닉네임과 함께 기록해보세요.';
      case _BestRecordUpdateKind.scoreAndStage:
        return '최고 점수와 최고 스테이지를 모두 갱신했어요. 닉네임과 함께 기록해보세요.';
    }
  }

  String get savedMessage {
    switch (this) {
      case _BestRecordUpdateKind.firstRecord:
        return '첫 기록이';
      case _BestRecordUpdateKind.scoreOnly:
        return '최고 점수가';
      case _BestRecordUpdateKind.stageOnly:
        return '최고 스테이지 기록이';
      case _BestRecordUpdateKind.scoreAndStage:
        return '최고 기록이';
    }
  }
}

class _NicknamePromptDialog extends StatefulWidget {
  const _NicknamePromptDialog({
    required this.initialNickname,
    required this.result,
    required this.updateKind,
  });

  final String initialNickname;
  final GameResult result;
  final _BestRecordUpdateKind updateKind;

  @override
  State<_NicknamePromptDialog> createState() => _NicknamePromptDialogState();
}

class _NicknamePromptDialogState extends State<_NicknamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNickname,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      return;
    }
    Navigator.of(context).pop(nickname);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.updateKind.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.updateKind.promptMessage,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.lightBlue.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Stage ${widget.result.lastStage} · ${widget.result.score}점',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey.shade800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: '닉네임',
              hintText: '닉네임을 입력하세요',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('건너뛰기'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class CloudConnectPage extends StatefulWidget {
  const CloudConnectPage({super.key});

  @override
  State<CloudConnectPage> createState() => _CloudConnectPageState();
}

enum _StageStatus { loading, playing, success, failure }

class _CloudNode {
  const _CloudNode({required this.position, required this.isDanger});

  final Offset position;
  final bool isDanger;
}

class _CloudConnectPageState extends State<CloudConnectPage>
    with SingleTickerProviderStateMixin {
  static const double _cloudRadius = 36;
  static const double _cloudIconSize = 64;
  static const double _stagePadding = 24;

  final Random _random = Random();

  int _stage = 1;
  _StageStatus _status = _StageStatus.loading;
  List<_CloudNode> _safeNodes = const [];
  List<_CloudNode> _dangerNodes = const [];
  final Set<int> _visitedSafeNodes = <int>{};
  List<Offset> _pathPoints = <Offset>[];
  int _pathVersion = 0;
  Timer? _timer;
  Timer? _nextStageTimer;
  int _timeLeft = 0;
  int _stageTimeLimit = 0;
  int _score = 0;
  int _nextStageCountdown = 0;
  bool _nextStagePaused = false;
  Size? _playAreaSize;
  String? _statusMessage;
  bool _touchActive = false;
  GameResult? _failureSummary;
  late final AnimationController _fireworksController;
  bool _showFireworks = false;
  Future<void>? _audioReady;
  late final AudioPlayer _clearPlayer;
  late final AudioPlayer _milestonePlayer;
  late final AudioPlayer _failPlayer;

  Future<void> _prepareAudio() async {
    _clearPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _milestonePlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _failPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

    await Future.wait(<Future<void>>[
      _clearPlayer.setSourceAsset('audio/clear.wav'),
      _milestonePlayer.setSourceAsset('audio/milestone.wav'),
      _failPlayer.setSourceAsset('audio/fail.wav'),
    ]);

    await Future.wait(<Future<void>>[
      _clearPlayer.setVolume(0.7),
      _milestonePlayer.setVolume(0.75),
      _failPlayer.setVolume(0.65),
    ]);
  }

  Future<void> _playCompletionSound({required bool milestone}) async {
    await (_audioReady ?? Future<void>.value());
    final AudioPlayer player = milestone ? _milestonePlayer : _clearPlayer;
    await player.seek(Duration.zero);
    await player.resume();
  }

  Future<void> _playFailureSound() async {
    await (_audioReady ?? Future<void>.value());
    await _failPlayer.seek(Duration.zero);
    await _failPlayer.resume();
  }

  @override
  void initState() {
    super.initState();
    _audioReady = _prepareAudio();
    _fireworksController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) {
            return;
          }
          setState(() {
            _showFireworks = false;
          });
        }
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nextStageTimer?.cancel();
    _clearPlayer.dispose();
    _milestonePlayer.dispose();
    _failPlayer.dispose();
    _fireworksController.dispose();
    super.dispose();
  }

  void _onStageAreaReady(Size size) {
    if (!mounted) {
      return;
    }

    final hasSizeChanged =
        _playAreaSize == null ||
        _playAreaSize!.width != size.width ||
        _playAreaSize!.height != size.height;

    if (hasSizeChanged) {
      setState(() {
        _playAreaSize = size;
      });
      _beginStage();
      return;
    }

    if (_status == _StageStatus.loading) {
      _beginStage();
    }
  }

  void _beginStage({bool incrementStage = false}) {
    _timer?.cancel();
    _nextStageTimer?.cancel();
    _fireworksController.stop();
    _fireworksController.reset();

    if (incrementStage) {
      _stage += 1;
    }

    final playArea = _playAreaSize;
    if (playArea == null) {
      setState(() {
        _status = _StageStatus.loading;
      });
      return;
    }

    final int safeCount = _stage + 1;
    final int dangerCount = _computeDangerCount();
    final ({List<_CloudNode> safeNodes, List<_CloudNode> dangerNodes})
    stageNodes = _generateStageNodes(
      safeCount: safeCount,
      dangerCount: dangerCount,
      area: playArea,
    );
    final int stageTimeLimit = _computeTimeLimit(safeCount);

    _timer?.cancel();

    setState(() {
      _safeNodes = stageNodes.safeNodes;
      _dangerNodes = stageNodes.dangerNodes;
      _visitedSafeNodes.clear();
      _pathPoints = <Offset>[];
      _pathVersion += 1;
      _status = _StageStatus.playing;
      _statusMessage = null;
      _touchActive = false;
      _stageTimeLimit = stageTimeLimit;
      _timeLeft = stageTimeLimit;
      _failureSummary = null;
      _showFireworks = false;
      _nextStageCountdown = 0;
      _nextStagePaused = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_status != _StageStatus.playing) {
        timer.cancel();
        return;
      }

      if (_timeLeft <= 1) {
        timer.cancel();
        _failStage('시간 초과! 다시 시도해보세요.');
      } else {
        setState(() {
          _timeLeft -= 1;
        });
      }
    });
  }

  int _computeTimeLimit(int safeCount) {
    final int stage = _stage;
    final base = 8;
    final perNode = 3;
    final computed = base + safeCount * perNode;

    if (stage >= 40) {
      return 20;
    }
    if (stage >= 30) {
      return 25;
    }
    return computed.clamp(8, 30);
  }

  int _computeDangerCount() {
    if (_stage < 2) {
      return 0;
    }

    int minCount;
    List<double> slotProbabilities;
    if (_stage < 4) {
      minCount = 0;
      slotProbabilities = <double>[0.6];
    } else if (_stage < 10) {
      minCount = 0;
      slotProbabilities = <double>[0.6, 0.42];
    } else if (_stage < 20) {
      minCount = 1;
      slotProbabilities = <double>[1.0, 0.55, 0.45];
    } else if (_stage < 30) {
      minCount = 2;
      slotProbabilities = <double>[1.0, 1.0, 0.52, 0.4];
    } else if (_stage < 40) {
      minCount = 3;
      slotProbabilities = <double>[1.0, 1.0, 1.0, 0.44, 0.32];
    } else {
      minCount = 4;
      slotProbabilities = <double>[1.0, 1.0, 1.0, 1.0, 0.42, 0.32, 0.24];
    }

    final int maxCount = slotProbabilities.length;
    int dangerCount = minCount;
    final double probabilityBoost = _dangerProbabilityBoost();

    for (int i = 0; i < maxCount; i += 1) {
      if (i < minCount) {
        continue;
      }

      double probability = slotProbabilities[i];
      if (probability >= 1.0) {
        dangerCount += 1;
        continue;
      }

      final double adjusted = (probability + probabilityBoost).clamp(0.0, 0.98);
      if (_random.nextDouble() < adjusted) {
        dangerCount += 1;
      }
    }

    if (dangerCount < minCount) {
      return minCount;
    }
    if (dangerCount > maxCount) {
      return maxCount;
    }
    return dangerCount;
  }

  double _dangerProbabilityBoost() {
    double boost = 0.0;
    if (_stage >= 40) {
      boost += (_stage - 39) * 0.03;
    }
    if (_stage >= 50 && _stage % 10 == 0) {
      boost += 0.03;
    }
    return boost;
  }

  ({List<_CloudNode> safeNodes, List<_CloudNode> dangerNodes})
  _generateStageNodes({
    required int safeCount,
    required int dangerCount,
    required Size area,
  }) {
    final List<_CloudNode> safeNodes = <_CloudNode>[];
    final List<_CloudNode> dangerNodes = <_CloudNode>[];
    final List<Offset> occupied = <Offset>[];

    Offset randomPosition() {
      final double maxWidth = max(area.width - _stagePadding * 2, 0);
      final double maxHeight = max(area.height - _stagePadding * 2, 0);
      final double dx = _stagePadding + _random.nextDouble() * maxWidth;
      final double dy = _stagePadding + _random.nextDouble() * maxHeight;
      return Offset(dx, dy);
    }

    bool canPlace(Offset candidate, double minDistance) {
      for (final Offset other in occupied) {
        if ((candidate - other).distance < minDistance) {
          return false;
        }
      }
      return true;
    }

    Offset jitter(Offset base, double radius) {
      final double angle = _random.nextDouble() * 2 * pi;
      final double magnitude = _random.nextDouble() * radius;
      final Offset offset = Offset(
        cos(angle) * magnitude,
        sin(angle) * magnitude,
      );
      final double dx = (base.dx + offset.dx)
          .clamp(_stagePadding, area.width - _stagePadding);
      final double dy = (base.dy + offset.dy)
          .clamp(_stagePadding, area.height - _stagePadding);
      return Offset(dx, dy);
    }

    void fillNodes({
      required List<_CloudNode> target,
      required int targetCount,
      required bool isDanger,
      required double initialDistance,
      required double minDistanceFloor,
    }) {
      double currentDistance = initialDistance;
      int failureStreak = 0;
      int attempts = 0;
      const int maxAttempts = 15000;

      while (target.length < targetCount && attempts < maxAttempts) {
        attempts += 1;
        final Offset candidate = randomPosition();
        if (canPlace(candidate, currentDistance)) {
          target.add(_CloudNode(position: candidate, isDanger: isDanger));
          occupied.add(candidate);
          failureStreak = 0;
          continue;
        }

        failureStreak += 1;

        if (failureStreak >= 450 && currentDistance > minDistanceFloor) {
          currentDistance = max(minDistanceFloor, currentDistance * 0.95);
          failureStreak = 0;
        }
      }

      if (target.length < targetCount) {
        final List<_CloudNode> snapshot = List<_CloudNode>.from(target);
        target
          ..clear()
          ..addAll(snapshot)
          ..addAll(
            List<_CloudNode>.generate(
              targetCount - snapshot.length,
              (_) => const _CloudNode(position: Offset.zero, isDanger: false),
            ),
          );
        for (int i = 0; i < target.length; i += 1) {
          if (i < snapshot.length) {
            continue;
          }
          Offset candidate = randomPosition();
          int localAttempts = 0;
          while (!canPlace(candidate, minDistanceFloor * 0.6) &&
              localAttempts < 2000) {
            candidate = jitter(candidate, minDistanceFloor * 0.4);
            localAttempts += 1;
          }
          final _CloudNode node = _CloudNode(
            position: candidate,
            isDanger: isDanger,
          );
          target[i] = node;
          occupied.add(candidate);
        }
      }

      if (target.length > targetCount) {
        target.removeRange(targetCount, target.length);
      }
    }

    fillNodes(
      target: safeNodes,
      targetCount: safeCount,
      isDanger: false,
      initialDistance: 116,
      minDistanceFloor: 74,
    );

    fillNodes(
      target: dangerNodes,
      targetCount: dangerCount,
      isDanger: true,
      initialDistance: 102,
      minDistanceFloor: 64,
    );

    return (safeNodes: safeNodes, dangerNodes: dangerNodes);
  }

  void _handlePanStart(Offset position) {
    if (_status != _StageStatus.playing) {
      return;
    }

    final int? safeIndex = _hitSafeNode(position);
    final bool hitDanger = _hitDangerNode(position) != null;

    if (hitDanger) {
      _failStage('비구름을 건드렸어요!');
      return;
    }

    if (safeIndex == null) {
      _failStage('구름 위에서 시작해보세요.');
      return;
    }

    setState(() {
      _touchActive = true;
      _pathPoints = <Offset>[position];
      _pathVersion += 1;
      _visitedSafeNodes
        ..clear()
        ..add(safeIndex);
    });

    if (_visitedSafeNodes.length == _safeNodes.length) {
      _completeStage();
    }
  }

  void _handlePanUpdate(Offset position) {
    if (_status != _StageStatus.playing || !_touchActive) {
      return;
    }

    if (_pathPoints.isNotEmpty &&
        _wouldIntersectExistingPath(_pathPoints.last, position)) {
      _failStage('이미 그은 선을 건드렸어요!');
      return;
    }

    if (_pathPoints.isEmpty || (_pathPoints.last - position).distance > 4) {
      setState(() {
        if (_pathPoints.isEmpty) {
          _pathPoints = <Offset>[position];
        } else {
          _pathPoints.add(position);
        }
        _pathVersion += 1;
      });
    }

    final int? dangerIndex = _hitDangerNode(position);
    if (dangerIndex != null) {
      _failStage('비구름을 건드렸어요!');
      return;
    }

    final int? safeIndex = _hitSafeNode(position);
    if (safeIndex != null) {
      final bool alreadyVisited = _visitedSafeNodes.contains(safeIndex);
      final int? lastVisited =
          _visitedSafeNodes.isNotEmpty ? _visitedSafeNodes.last : null;

      if (alreadyVisited && safeIndex != lastVisited) {
        _failStage('이미 방문한 구름을 다시 건드렸어요!');
        return;
      }

      if (!alreadyVisited) {
        setState(() {
          _visitedSafeNodes.add(safeIndex);
        });
        if (_visitedSafeNodes.length == _safeNodes.length) {
          _completeStage();
        }
      }
    }
  }

  void _handlePanEnd() {
    if (_status != _StageStatus.playing || !_touchActive) {
      return;
    }

    if (_visitedSafeNodes.length == _safeNodes.length) {
      return;
    }

    _failStage('손을 떼지 않고 모든 구름을 이어야 해요.');
  }

  void _completeStage() {
    if (_status != _StageStatus.playing) {
      return;
    }

    final int stageNumber = _stage;
    final int timeRemaining = max(_timeLeft, 0);
    final int timeSpent = (_stageTimeLimit - timeRemaining)
        .clamp(0, _stageTimeLimit)
        .toInt();
    final int stageScore = stageNumber * 100 + timeRemaining * 5;
    final bool isMilestoneStage = stageNumber > 0 && stageNumber % 10 == 0;
    final int milestone = isMilestoneStage ? stageNumber : 0;
    final String baseMessage =
        'Stage $stageNumber 클리어! +$stageScore점 (시간 $timeSpent초)';

    _timer?.cancel();
    _nextStageTimer?.cancel();
    HapticFeedback.selectionClick();
    unawaited(_playCompletionSound(milestone: isMilestoneStage));
    setState(() {
      _score += stageScore;
      _status = _StageStatus.success;
      _statusMessage = isMilestoneStage
          ? '$baseMessage\n\n$milestone단계 돌파! 축하해요!'
          : baseMessage;
      _touchActive = false;
      _failureSummary = null;
      if (isMilestoneStage) {
        _showFireworks = true;
      }
      _nextStageCountdown = 3;
      _nextStagePaused = false;
    });

    if (isMilestoneStage) {
      _fireworksController.forward(from: 0);
    }

    _startNextStageCountdown();
  }

  void _failStage(String message) {
    if (_status != _StageStatus.playing) {
      return;
    }

    _timer?.cancel();
    _nextStageTimer?.cancel();

    HapticFeedback.heavyImpact();
    unawaited(_playFailureSound());

    setState(() {
      _status = _StageStatus.failure;
      _statusMessage = message;
      _touchActive = false;
      _failureSummary = GameResult(lastStage: _stage, score: _score);
      _nextStageCountdown = 0;
      _nextStagePaused = false;
    });
  }

  void _startNextStageCountdown() {
    if (!mounted || _status != _StageStatus.success) {
      return;
    }

    _nextStageTimer?.cancel();

    if (_nextStagePaused) {
      return;
    }

    if (_nextStageCountdown <= 0) {
      _beginStage(incrementStage: true);
      return;
    }

    _nextStageTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_status != _StageStatus.success || _nextStagePaused) {
        timer.cancel();
        return;
      }
      if (_nextStageCountdown <= 1) {
        timer.cancel();
        setState(() {
          _nextStageCountdown = 0;
        });
        _beginStage(incrementStage: true);
      } else {
        setState(() {
          _nextStageCountdown -= 1;
        });
      }
    });
  }

  void _toggleNextStagePause() {
    if (_status != _StageStatus.success) {
      return;
    }

    if (_nextStagePaused) {
      setState(() {
        _nextStagePaused = false;
        _nextStageCountdown = 0;
      });
      _beginStage(incrementStage: true);
    } else {
      _nextStageTimer?.cancel();
      setState(() {
        _nextStagePaused = true;
      });
    }
  }

  void _handleFailureAcknowledged() {
    final GameResult? summary = _failureSummary;
    Navigator.of(
      context,
    ).pop(summary ?? GameResult(lastStage: _stage, score: _score));
  }

  int? _hitSafeNode(Offset position) {
    for (int i = 0; i < _safeNodes.length; i += 1) {
      if ((position - _safeNodes[i].position).distance <= _cloudRadius) {
        return i;
      }
    }
    return null;
  }

  int? _hitDangerNode(Offset position) {
    for (int i = 0; i < _dangerNodes.length; i += 1) {
      if ((position - _dangerNodes[i].position).distance <= _cloudRadius) {
        return i;
      }
    }
    return null;
  }

  bool _wouldIntersectExistingPath(Offset from, Offset to) {
    if (_pathPoints.length < 2) {
      return false;
    }

    for (int i = 0; i < _pathPoints.length - 1; i += 1) {
      final Offset start = _pathPoints[i];
      final Offset end = _pathPoints[i + 1];

      if (_pointsClose(start, from) || _pointsClose(end, from)) {
        continue;
      }

      if (_segmentsIntersect(start, end, from, to)) {
        return true;
      }
    }

    return false;
  }

  bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    if (_pointsClose(p1, p2) || _pointsClose(q1, q2)) {
      return false;
    }

    final double o1 = _orientation(p1, p2, q1);
    final double o2 = _orientation(p1, p2, q2);
    final double o3 = _orientation(q1, q2, p1);
    final double o4 = _orientation(q1, q2, p2);

    const double epsilon = 1e-6;

    if (((o1 > epsilon && o2 < -epsilon) || (o1 < -epsilon && o2 > epsilon)) &&
        ((o3 > epsilon && o4 < -epsilon) || (o3 < -epsilon && o4 > epsilon))) {
      return true;
    }

    if (o1.abs() <= epsilon && _onSegment(p1, p2, q1)) {
      return true;
    }
    if (o2.abs() <= epsilon && _onSegment(p1, p2, q2)) {
      return true;
    }
    if (o3.abs() <= epsilon && _onSegment(q1, q2, p1)) {
      return true;
    }
    if (o4.abs() <= epsilon && _onSegment(q1, q2, p2)) {
      return true;
    }

    return false;
  }

  double _orientation(Offset a, Offset b, Offset c) {
    final Offset ab = b - a;
    final Offset ac = c - a;
    return ab.dx * ac.dy - ab.dy * ac.dx;
  }

  bool _onSegment(Offset a, Offset b, Offset c) {
    final double minX = min(a.dx, b.dx) - 1e-6;
    final double maxX = max(a.dx, b.dx) + 1e-6;
    final double minY = min(a.dy, b.dy) - 1e-6;
    final double maxY = max(a.dy, b.dy) + 1e-6;
    return c.dx >= minX && c.dx <= maxX && c.dy >= minY && c.dy <= maxY;
  }

  bool _pointsClose(Offset a, Offset b) {
    return (a - b).distance <= 1e-6;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue.shade50,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  BackButton(
                    color: Colors.blueGrey.shade700,
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Stage $_stage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '남은 시간',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blueGrey.shade500,
                            ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: child,
                          );
                        },
                        child: Text(
                          '$_timeLeft초',
                          key: ValueKey<int>(_timeLeft),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: _timeLeft <= 5
                                    ? Colors.redAccent
                                    : Colors.blueGrey,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        '점수',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blueGrey.shade500,
                            ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: child,
                          );
                        },
                        child: Text(
                          '$_score점',
                          key: ValueKey<int>(_score),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.blueGrey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '구름들을 손을 떼지 않고 모두 이어주세요.\n검은 비구름은 피해야 해요!',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _onStageAreaReady(size),
                  );

                  if (_playAreaSize == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                Colors.lightBlue.shade100,
                                Colors.lightBlue.shade50,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      AbsorbPointer(
                        absorbing: _status != _StageStatus.playing,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (DragStartDetails details) =>
                              _handlePanStart(details.localPosition),
                          onPanUpdate: (DragUpdateDetails details) =>
                              _handlePanUpdate(details.localPosition),
                          onPanEnd: (_) => _handlePanEnd(),
                          onPanCancel: _handlePanEnd,
                          child: CustomPaint(
                            painter: _CloudPathPainter(
                              points: _pathPoints,
                              version: _pathVersion,
                            ),
                            child: Stack(
                              children: <Widget>[..._buildCloudWidgets()],
                            ),
                          ),
                        ),
                      ),
                      if (_showFireworks)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _fireworksController,
                              builder:
                                  (BuildContext context, Widget? child) {
                                final double value =
                                    _fireworksController.value.clamp(0.0, 1.0);
                                final double opacity = (1 -
                                        Curves.easeInCubic.transform(value))
                                    .clamp(0.0, 1.0);
                                if (opacity <= 0) {
                                  return const SizedBox.shrink();
                                }
                                return Opacity(
                                  opacity: opacity,
                                  child: CustomPaint(
                                    painter: _FireworksPainter(
                                      progress: value,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      if (_status == _StageStatus.success &&
                          _statusMessage != null)
                        Positioned.fill(
                          child: AnimatedOpacity(
                            opacity: 1,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              color: Colors.black45,
                              alignment: Alignment.center,
                              child: Container(
                                width: min(360, constraints.maxWidth * 0.9),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Text(
                                      _statusMessage!,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 16),
                                    if (_nextStagePaused)
                                      Text(
                                        '일시 정지됨 - 준비가 되면 재개를 눌러주세요.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Colors.blueGrey.shade600,
                                            ),
                                      )
                                    else if (_nextStageCountdown > 0)
                                      Text(
                                        '다음 스테이지까지 $_nextStageCountdown초',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Colors.blueGrey.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    if (_nextStagePaused || _nextStageCountdown > 0)
                                      const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Builder(
                                        builder: (BuildContext context) {
                                          if (_nextStagePaused) {
                                            return FilledButton.tonal(
                                              onPressed: _toggleNextStagePause,
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Colors.green.shade600,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('계속 하기'),
                                            );
                                          }
                                          return FilledButton(
                                            onPressed: _toggleNextStagePause,
                                            child: const Text('일시 정지 하기'),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_status == _StageStatus.failure &&
                          _failureSummary != null)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: Container(
                              width: min(340, constraints.maxWidth * 0.85),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 24,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    _statusMessage ?? '게임 오버',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey.shade800,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  _FailureSummaryView(
                                    summary: _failureSummary!,
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: _handleFailureAcknowledged,
                                      child: const Text('확인'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_status == _StageStatus.loading)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white70,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCloudWidgets() {
    final List<Widget> widgets = <Widget>[];

    for (int i = 0; i < _safeNodes.length; i += 1) {
      final _CloudNode node = _safeNodes[i];
      final bool visited = _visitedSafeNodes.contains(i);
      widgets.add(
        Positioned(
          left: node.position.dx - _cloudIconSize / 2,
          top: node.position.dy - _cloudIconSize / 2,
          child: _CloudWidget(
            iconSize: _cloudIconSize,
            color: visited ? Colors.blueAccent : Colors.white,
            iconColor: visited ? Colors.white : Colors.blueGrey.shade700,
            shadowColor: Colors.blueGrey.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    for (final _CloudNode node in _dangerNodes) {
      widgets.add(
        Positioned(
          left: node.position.dx - _cloudIconSize / 2,
          top: node.position.dy - _cloudIconSize / 2,
          child: _CloudWidget(
            iconSize: _cloudIconSize,
            color: Colors.black87,
            iconColor: Colors.white,
            shadowColor: Colors.black54,
            icon: Icons.thunderstorm,
          ),
        ),
      );
    }

    return widgets;
  }
}

class _FailureSummaryView extends StatelessWidget {
  const _FailureSummaryView({required this.summary});

  final GameResult summary;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.flag, color: Colors.lightBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              '플레이한 스테이지',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Stage ${summary.lastStage}',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            const Icon(Icons.stars, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              '총 점수',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${summary.score}점',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
      ],
    );
  }
}

class _CloudWidget extends StatelessWidget {
  const _CloudWidget({
    required this.iconSize,
    required this.color,
    required this.iconColor,
    required this.shadowColor,
    this.icon,
  });

  final double iconSize;
  final Color color;
  final Color iconColor;
  final Color shadowColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon ?? Icons.cloud, color: iconColor, size: iconSize * 0.55),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  const _FireworksPainter({required this.progress});

  final double progress;

  static const List<_FireworkBurst> _bursts = <_FireworkBurst>[
    _FireworkBurst(0.22, 0.28, Color(0xFF8BC9FF), scale: 0.9),
    _FireworkBurst(0.78, 0.26, Color(0xFFFFC778)),
    _FireworkBurst(0.52, 0.18, Color(0xFFB39DDB), scale: 1.1),
    _FireworkBurst(0.32, 0.64, Color(0xFF4DD0E1)),
    _FireworkBurst(0.7, 0.66, Color(0xFFFF8A80), scale: 0.95),
  ];

  static const List<_FireworkConfetti> _confetti = <_FireworkConfetti>[
    _FireworkConfetti(0.18, 0.48, Color(0xFFFFEB3B)),
    _FireworkConfetti(0.82, 0.5, Color(0xFF4CAF50)),
    _FireworkConfetti(0.12, 0.7, Color(0xFFFF7043)),
    _FireworkConfetti(0.88, 0.72, Color(0xFF64B5F6)),
    _FireworkConfetti(0.5, 0.78, Color(0xFFE57373)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double clamped = progress.clamp(0.0, 1.0);
    final double eased = Curves.easeOutQuart.transform(clamped);
    final double fade =
        (1.0 - Curves.easeInCubic.transform(clamped)).clamp(0.0, 1.0);

    for (final _FireworkBurst burst in _bursts) {
      final Offset center = Offset(
        burst.dx * size.width,
        burst.dy * size.height,
      );

      final double radius =
          size.shortestSide * (0.08 + eased * 0.22) * burst.scale;
      final double length = radius * (0.8 + eased * 0.6);
      final double lineAlpha =
          (0.55 + 0.35 * fade).clamp(0.0, 1.0).toDouble();
      final Paint linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = burst.color.withValues(alpha: lineAlpha)
        ..strokeWidth = 3.2 * (1 - 0.6 * eased);

      const int sparkCount = 12;
      for (int i = 0; i < sparkCount; i += 1) {
        final double angle = (2 * pi / sparkCount) * i;
        final Offset end = center + Offset(cos(angle), sin(angle)) * length;
        canvas.drawLine(center, end, linePaint);
        final double dotAlpha =
            (0.45 + 0.45 * fade).clamp(0.0, 1.0).toDouble();
        final Paint dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = burst.color.withValues(alpha: dotAlpha);
        final double sparkleRadius = radius * 0.08 * (1 - eased) + 2.4;
        canvas.drawCircle(end, sparkleRadius, dotPaint);
      }

      final double haloAlpha =
          (0.28 + 0.4 * fade).clamp(0.0, 1.0).toDouble();
      final Paint haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = burst.color.withValues(alpha: haloAlpha);
      canvas.drawCircle(center, radius * (0.38 + eased * 0.32), haloPaint);
    }

    final Paint confettiPaint = Paint()..style = PaintingStyle.fill;
    for (final _FireworkConfetti confetti in _confetti) {
      final double fall = size.height * 0.08 * eased;
      final Offset position = Offset(
        confetti.dx * size.width,
        confetti.dy * size.height + fall,
      );
      confettiPaint.color = confetti.color.withValues(
        alpha: (0.4 + 0.6 * fade).clamp(0.0, 1.0).toDouble(),
      );
      canvas.drawCircle(position, size.shortestSide * 0.015, confettiPaint);
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _FireworkBurst {
  const _FireworkBurst(this.dx, this.dy, this.color, {this.scale = 1.0});

  final double dx;
  final double dy;
  final Color color;
  final double scale;
}

class _FireworkConfetti {
  const _FireworkConfetti(this.dx, this.dy, this.color);

  final double dx;
  final double dy;
  final Color color;
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.title,
    required this.stageLabel,
    required this.scoreLabel,
    required this.timestamp,
    this.highlight = false,
  });

  final String title;
  final String stageLabel;
  final String scoreLabel;
  final String timestamp;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color baseColor = highlight
        ? scheme.primaryContainer.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.9);
    final Color borderColor = highlight
        ? scheme.primary.withValues(alpha: 0.35)
        : Colors.blueGrey.withValues(alpha: 0.08);
    final Color titleColor = highlight
        ? scheme.primary.withValues(alpha: 0.9)
        : Colors.blueGrey.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.blueGrey.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              if (highlight)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.emoji_events_outlined,
                    size: 20,
                    color: scheme.primary.withValues(alpha: 0.9),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  stageLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ),
              Text(
                scoreLabel,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            timestamp,
            style: textTheme.bodySmall?.copyWith(
              color: Colors.blueGrey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.stage});

  final int stage;

  static const List<Color> _palette = <Color>[
    Color(0xFF3A7BD5),
    Color(0xFFBA68C8),
    Color(0xFFFFB74D),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
    Color(0xFF9575CD),
    Color(0xFFFF8A65),
    Color(0xFF4FC3F7),
    Color(0xFFAED581),
    Color(0xFF7986CB),
  ];

  Color _backgroundColor() {
    if (stage <= 0) {
      return Colors.lightBlue.shade100;
    }
    final int decadeIndex = stage ~/ 10;
    if (decadeIndex <= 0) {
      return Colors.lightBlue.shade100;
    }
    final int paletteIndex = (decadeIndex - 1) % _palette.length;
    return _palette[paletteIndex].withValues(alpha: 0.9);
  }

  Color _foregroundColor(Color background) {
    final double luminance = background.computeLuminance();
    return luminance > 0.45 ? Colors.blueGrey.shade800 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = _backgroundColor();
    final Color fg = _foregroundColor(bg);

    return CircleAvatar(
      radius: 22,
      backgroundColor: bg,
      child: Text(
        '$stage',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _CloudPathPainter extends CustomPainter {
  const _CloudPathPainter({required this.points, required this.version});

  final List<Offset> points;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    final Paint paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CloudPathPainter oldDelegate) {
    if (oldDelegate.version != version) {
      return true;
    }
    if (!identical(oldDelegate.points, points)) {
      if (oldDelegate.points.length != points.length) {
        return true;
      }
      for (int i = 0; i < points.length; i += 1) {
        if (oldDelegate.points[i] != points[i]) {
          return true;
        }
      }
    }
    return false;
  }
}
