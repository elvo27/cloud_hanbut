# 구름 친구 맺기

손을 떼지 않고 안전한 구름을 모두 이어가는 Flutter 퍼즐 게임입니다. iOS와 Android를 지원하며 로컬 플레이 기록, Supabase 공개 랭킹, Google AdMob 배너 광고를 포함합니다.

## 실행과 검증

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

디버그 빌드는 Google 테스트 광고 단위를 사용합니다. 릴리스 빌드는 기본적으로 실제 광고 단위를 사용하므로, TestFlight 및 내부 QA 빌드에는 반드시 다음 플래그를 사용합니다.

```sh
flutter build ipa --release --dart-define=USE_TEST_ADS=true
```

광고 기능 전체를 끄려면 `--dart-define=ADS_ENABLED=false`를 추가합니다.

## 광고 배치 원칙

- 메인, 내 기록, 다른 사람 기록 화면에만 적응형 배너를 표시합니다.
- 플레이 화면에는 광고를 표시하지 않습니다.
- 전면 및 보상형 광고 단위 ID는 플랫폼별 설정에 보관하지만 현재 릴리스에서는 로드하거나 표시하지 않습니다.
- 광고 요청은 아동 대상 및 동의 연령 미만, 최대 G등급으로 제한합니다.
- 동의 상태가 광고 요청을 허용한 뒤에만 Mobile Ads SDK를 초기화합니다.

## 랭킹 운영

`supabase/migrations`에 공개 랭킹의 입력 검증, 기록 소유권, 신고 및 자동 숨김 정책이 있습니다. 운영 DB에 적용하기 전 현재 스키마와 백업 정책을 확인해야 합니다. 앱은 신규 RPC가 아직 배포되지 않은 환경에서도 기존 기록 제출 RPC로 폴백합니다.

개인정보처리방침은 `privacy-policy-ko.html`과 `privacy-policy-en.html`에서 관리하며 공개 URL은 다음과 같습니다.

- https://elvo27.github.io/cloud_hanbut/privacy-policy-ko.html
- https://elvo27.github.io/cloud_hanbut/privacy-policy-en.html

AdMob 소유권 검증 파일은 https://elvo27.github.io/app-ads.txt 에 게시되어 있습니다.
