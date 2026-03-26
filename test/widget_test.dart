// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
