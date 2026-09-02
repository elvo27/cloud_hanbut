import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hanbut/game_high_score_repository.dart';
import 'package:hanbut/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('메인 화면에서 게임을 시작하면 스테이지가 나타난다', (WidgetTester tester) async {
    await tester.pumpWidget(const HanbutApp());

    expect(find.text('구름 친구 맺기'), findsOneWidget);
    expect(find.text('Stage 1'), findsNothing);

    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();

    expect(find.text('Stage 1'), findsOneWidget);
    expect(find.text('0점'), findsOneWidget);
    expect(
      find.text('구름들을 손을 떼지 않고 모두 이어주세요.\n검은 비구름은 피해야 해요!'),
      findsOneWidget,
    );
  });

  testWidgets('내 기록 보기 버튼과 다른 사람 기록 보기 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const HanbutApp());
    await tester.pumpAndSettle();

    expect(find.text('내 기록 보기'), findsOneWidget);
    expect(find.text('다른 사람 기록 보기'), findsOneWidget);
  });

  testWidgets('저장된 내 기록을 시트에서 볼 수 있다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloud_connect_history': <String>[
        jsonEncode(<String, dynamic>{
          'lastStage': 6,
          'score': 420,
          'finishedAt': '2026-03-26T03:15:00.000Z',
        }),
      ],
    });

    await tester.pumpWidget(const HanbutApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 기록 보기'));
    await tester.pumpAndSettle();

    expect(find.text('내 기록'), findsOneWidget);
    expect(find.text('Stage 6'), findsAtLeastNWidgets(1));
    expect(find.text('420점 · 2026.03.26 12:15'), findsOneWidget);
  });

  testWidgets('다른 사람 기록 시트에서 정렬 조건을 바꾸면 새로 조회한다', (WidgetTester tester) async {
    final FakeGameHighScoreRepository repository = FakeGameHighScoreRepository(
      fetchResults: <RemoteHighScoreSort, List<RemoteHighScoreEntry>>{
        RemoteHighScoreSort.score: <RemoteHighScoreEntry>[
          RemoteHighScoreEntry(
            nickname: 'ScoreUser',
            score: 500,
            lastStage: 8,
            playedAt: DateTime(2026, 3, 26, 12),
          ),
        ],
        RemoteHighScoreSort.topStage: <RemoteHighScoreEntry>[
          RemoteHighScoreEntry(
            nickname: 'StageUser',
            score: 300,
            lastStage: 12,
            playedAt: DateTime(2026, 3, 25, 12),
          ),
        ],
      },
    );

    await tester.pumpWidget(
      HanbutApp(home: HomePage(highScoreRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('다른 사람 기록 보기'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.fetchSorts.first, RemoteHighScoreSort.score);
    expect(find.text('ScoreUser'), findsOneWidget);

    await tester.tap(find.text('최고스테이지 순'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.fetchSorts.last, RemoteHighScoreSort.topStage);
    expect(find.text('StageUser'), findsOneWidget);
  });

  testWidgets('최고 스테이지만 갱신해도 닉네임 입력 다이얼로그가 뜬다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloud_connect_history': <String>[
        jsonEncode(<String, dynamic>{
          'lastStage': 5,
          'score': 300,
          'finishedAt': '2026-03-25T03:15:00.000Z',
        }),
      ],
    });

    final FakeGameHighScoreRepository repository = FakeGameHighScoreRepository(
      fetchResults: const <RemoteHighScoreSort, List<RemoteHighScoreEntry>>{},
    );

    await tester.pumpWidget(
      HanbutApp(
        home: HomePage(
          highScoreRepository: repository,
          onPlayGame: () async => GameResult(
            lastStage: 6,
            score: 250,
            finishedAt: DateTime(2026, 3, 26, 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();

    expect(find.text('최고 스테이지 갱신'), findsOneWidget);
    expect(find.textContaining('닉네임과 함께 기록해보세요.'), findsOneWidget);
  });

  testWidgets('갱신이 아닐 때는 Supabase 저장 다이얼로그가 뜨지 않는다', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloud_connect_history': <String>[
        jsonEncode(<String, dynamic>{
          'lastStage': 6,
          'score': 400,
          'finishedAt': '2026-03-25T03:15:00.000Z',
        }),
      ],
    });

    final FakeGameHighScoreRepository repository = FakeGameHighScoreRepository(
      fetchResults: const <RemoteHighScoreSort, List<RemoteHighScoreEntry>>{},
    );

    await tester.pumpWidget(
      HanbutApp(
        home: HomePage(
          highScoreRepository: repository,
          onPlayGame: () async => GameResult(
            lastStage: 5,
            score: 300,
            finishedAt: DateTime(2026, 3, 26, 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();

    expect(find.text('최고 점수 갱신'), findsNothing);
    expect(find.text('최고 스테이지 갱신'), findsNothing);
    expect(repository.submitCalls, isEmpty);
  });

  testWidgets('최고 점수 갱신 시 닉네임과 함께 점수 스테이지 시간이 저장된다', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloud_connect_history': <String>[
        jsonEncode(<String, dynamic>{
          'lastStage': 4,
          'score': 280,
          'finishedAt': '2026-03-24T03:15:00.000Z',
        }),
      ],
      'cloud_connect_nickname': 'SavedNick',
    });

    final FakeGameHighScoreRepository repository = FakeGameHighScoreRepository(
      fetchResults: const <RemoteHighScoreSort, List<RemoteHighScoreEntry>>{},
    );
    final DateTime finishedAt = DateTime(2026, 3, 26, 10, 30);

    await tester.pumpWidget(
      HanbutApp(
        home: HomePage(
          highScoreRepository: repository,
          onPlayGame: () async =>
              GameResult(lastStage: 4, score: 350, finishedAt: finishedAt),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();

    expect(find.text('최고 점수 갱신'), findsOneWidget);
    expect(find.text('SavedNick'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(repository.submitCalls, hasLength(1));
    expect(repository.submitCalls.single['gameName'], 'cloud_connect');
    expect(repository.submitCalls.single['nickname'], 'SavedNick');
    expect(repository.submitCalls.single['score'], 350);
    expect(repository.submitCalls.single['lastStage'], 4);
    expect(repository.submitCalls.single['playedAt'], finishedAt);
  });
}

class FakeGameHighScoreRepository extends GameHighScoreRepository {
  FakeGameHighScoreRepository({required this.fetchResults});

  final Map<RemoteHighScoreSort, List<RemoteHighScoreEntry>> fetchResults;
  final List<RemoteHighScoreSort> fetchSorts = <RemoteHighScoreSort>[];
  final List<Map<String, Object?>> submitCalls = <Map<String, Object?>>[];

  @override
  Future<List<RemoteHighScoreEntry>> fetchHighScores({
    required String gameName,
    int limit = 50,
    RemoteHighScoreSort sort = RemoteHighScoreSort.score,
  }) async {
    fetchSorts.add(sort);
    return fetchResults[sort] ?? const <RemoteHighScoreEntry>[];
  }

  @override
  Future<void> submitBestScore({
    required String gameName,
    required String nickname,
    required int score,
    int? lastStage,
    DateTime? playedAt,
    String? playerId,
  }) async {
    submitCalls.add(<String, Object?>{
      'gameName': gameName,
      'nickname': nickname,
      'score': score,
      'lastStage': lastStage,
      'playedAt': playedAt,
      'playerId': playerId,
    });
  }
}
