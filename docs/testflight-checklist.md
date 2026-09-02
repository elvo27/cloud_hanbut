# App Store 1.1.1 (38) 제출 체크리스트

## 빌드 전

- [ ] `flutter analyze` 오류 없음
- [ ] `flutter test` 전체 통과
- [ ] iOS 시뮬레이터에서 메인, 내 기록, 랭킹, 게임, 개인정보 화면 확인
- [ ] 디버그·내부 테스트는 테스트 광고, App Store Release는 실제 광고 단위 사용
- [ ] 실기기에서 UMP 동의 흐름과 적응형 배너 확인
- [ ] 개인정보처리방침 공개 URL 최신 내용 게시
- [ ] App Store Connect 개인정보 답변을 AdMob 및 공개 랭킹 데이터 흐름에 맞게 갱신

## 배포

```sh
flutter build ipa --release --dart-define=USE_TEST_ADS=true
```

- [ ] 번들 ID `com.cloud.hanbut`
- [ ] 버전 `1.1.1`, 빌드 `38`
- [ ] `testFlightInternalTestingOnly` 없이 App Store 제출 가능한 IPA 내보내기
- [ ] 처리 완료 후 App Store 버전에 빌드 연결
- [ ] 수동 출시(`MANUAL`)로 심사 제출하여 승인 후 자동 출시 방지

## 운영 전 필수

- [x] Supabase 리더보드·신고 보안 마이그레이션 적용 및 기존 75건 보존 확인
- [ ] 신고된 닉네임 검토·삭제 연락 절차 준비
- [ ] AdMob 앱과 실제 App Store/Google Play 등록 연결 및 app-ads.txt 확인
- [ ] App Store 개인정보 라벨을 AdMob·공개 랭킹 데이터 흐름에 맞게 게시
