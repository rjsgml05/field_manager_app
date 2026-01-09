import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_manager_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('팀장 전체 프로세스 테스트', () {
    testWidgets('1313 로그인 후 지도 마커 생성 테스트', (tester) async {
      app.main();
      
      // 1. 초기 로딩 대기 (사용자가 권한을 누를 시간을 벌어줌)
      print("앱 시작 및 권한 대기 중...");
      await Future.delayed(const Duration(seconds: 5)); 
      await tester.pump(); 

      // 2. 로그인 (1313 / 123)
      print("로그인 정보 입력 중...");
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '1313');
      await tester.enterText(textFields.at(1), '123');
      await tester.pump();
      
      // '로그인' 버튼 클릭 (텍스트로 찾기)
      await tester.tap(find.text('로그인'));
      
      // 로그인 후 지도가 로딩될 때까지 충분히 대기
      print("지도 로딩 대기 중...");
      await Future.delayed(const Duration(seconds: 8)); 
      await tester.pumpAndSettle();

      // 3. 지도 중앙 롱 터치 (가장 안정적인 좌표 방식)
      print("지도 중앙 롱 터치 시도");
      // 화면 정중앙 좌표 계산
      final center = tester.getCenter(find.byType(Scaffold).first);
      
      // 롱 프레스 실행
      await tester.longPressAt(center);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 4. 입력창이 떴는지 확인 후 제목 입력
      print("마커 제목 입력 중...");
      // 제목 입력 필드에 '자동 테스트 마커' 입력
      // (마지막에 나타난 TextField가 제목창인 경우가 많음)
      await tester.enterText(find.byType(TextField).last, '자동 테스트 마커');
      await tester.pump();

      // 5. 저장 완료 버튼 클릭
      print("저장 버튼 클릭");
      final saveBtn = find.text('저장 완료');
      if (saveBtn.evaluate().isNotEmpty) {
        await tester.tap(saveBtn);
      } else {
        // 텍스트로 못 찾으면 '확인'이나 마지막 버튼 클릭
        await tester.tap(find.byType(ElevatedButton).last);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 6. 검증: 지도로 돌아왔을 때 마커 제목이 화면에 있는지 확인
      expect(find.text('자동 테스트 마커'), findsOneWidget);
      print("✅ 테스트 완료: 마커가 성공적으로 생성되었습니다.");
    });
  });
}