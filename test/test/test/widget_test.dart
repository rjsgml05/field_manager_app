import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_manager_app/main.dart';

void main() {
  testWidgets('로그인 화면 UI 테스트', (WidgetTester tester) async {
    // 1. 테스트용 앱 실행
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(onLoginSuccess: (admin, name, pw) {}),
    ));

    // 2. "현장 관리 시스템"이라는 텍스트가 화면에 있는지 확인
    expect(find.text('현장 관리 시스템'), findsOneWidget);

    // 3. 로그인 버튼이 있는지 확인
    expect(find.byType(ElevatedButton), findsOneWidget);
    
    // 4. 팀명 입력창에 글자 써보기
    await tester.enterText(find.byType(TextField).first, 'test_team');
    expect(find.text('test_team'), findsOneWidget);
  });
}