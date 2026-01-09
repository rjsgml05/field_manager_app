import 'package:flutter_test/flutter_test.dart';
import 'package:field_manager_app/main.dart'; // 건희 님의 파일명에 맞게 수정

void main() {
  test('SiteData JSON 변환 테스트', () {
    // 1. 가상의 데이터 준비
    final json = {
      'id': 'test_123',
      'lat': 37.5,
      'lng': 127.0,
      'title': '테스트 현장',
      'description': '설명',
      'group': {'name': '그룹1', 'colorValue': 4280356608, 'isVisible': true},
      'photos': []
    };

    // 2. 함수 실행
    final site = SiteData.fromJson(json);

    // 3. 결과 확인 (기대한 값과 실제 값이 같은지 비교)
    expect(site.id, 'test_123');
    expect(site.title, '테스트 현장');
    expect(site.lat, 37.5);
  });
}