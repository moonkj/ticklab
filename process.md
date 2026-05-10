# TickLab — Watch Accuracy Pro · Process Log

> 시간순 진행 기록. Hyemi(리더)가 각 task 완료 후 갱신.
> 형식: `## YYYY-MM-DD · Task ID — Title`
> 본문: 결정 사항, 영향받는 레이어, 다음 task hand-off, 미해결 질문.

---

## 2026-05-10 · Phase 0 — Bootstrap

- 작업 디렉토리: `/Users/kjmoon/TickLab` (빈 디렉토리에서 시작)
- Git: `git init -b main` 완료
- 원격: `https://github.com/moonkj/ticklab.git` (빈 레포 확인)
- Bundle ID 확정: `com.ticklab.watchaccuracypro`
- 도구 확인: tmux 3.6a, Xcode 26.3, Swift 6.2.4, xcodegen, gh CLI 인증됨(moonkj)

### 운영 합의 사항
- 병렬 실행 방식: Claude Agent 서브에이전트(메인 컨텍스트 = Hyemi가 통합/조정)
- 코드 변경의 일관성 보장을 위해 실제 파일 쓰기는 메인 컨텍스트가 담당, 서브에이전트는 리뷰·디버깅·조사 위주
- Phase 1 전체(Week 1~6) 풀 자율 진행 — 단, 실기기 테스트가 필요한 단계(LiveWaveform 60fps 검증, DSP 정확도 ±2초/일 검증, TestFlight 베타)는 사용자 개입 포인트로 남김
- 한국어 default, 영어 보조

### 결정한 디렉토리/스킴 명명
- Xcode 스킴: `WatchAccuracyPro`
- iOS Deployment Target: 17.0
- Asset Catalog: `Resources/Assets.xcassets`
- 한국어가 development localization

---

## 2026-05-10 · Week 1 — 프로젝트 셋업 + 데이터 모델 완료

### 산출물
- xcodegen 기반 Xcode 프로젝트 (`WatchAccuracyPro.xcodeproj` 자동 생성, 커밋)
- SwiftData `@Model`: `Watch`, `WatchMeasurement` (Foundation `Measurement<Unit>` 충돌 회피)
- `MeasurementMetadata` (Codable struct, JSON-encoded `Data` 컬럼으로 저장)
- `Position`, `Escapement`, `ReliabilityLabel` enum
- `Movement` struct + `MovementDatabase` (싱글톤, 번들 JSON 로더)
- `MovementMatcher` (단순 키워드 매칭, Top 10 무브먼트 seed)
- `UI/Theme/Colors`, `Typography` 토큰
- `ko.lproj`/`en.lproj` Localizable.strings
- `WatchAccuracyProApp` (@main + ModelContainer) + 한/영 미리보기 가능한 `ContentView`
- 단위 테스트 14개 (ModelTests 4 + MovementDatabaseTests 5 + MovementMatcherTests 5)
- UI smoke 테스트 1개

### 검증 결과
- ✅ iOS 17.2 (iPhone 15 Pro) — 14/14 PASS
- ✅ iOS 26.2 (iPhone 17 Pro) — 14/14 PASS
- ✅ 빌드 SUCCEEDED 양쪽 OS

### Cross-layer note (Hyemi → 모든 팀원)

**SwiftData iOS 17.x cascade delete 버그**
- 증상: `@Relationship(deleteRule: .cascade, inverse: \WatchMeasurement.watch)` + 명시적 `try context.save()` 조합에서 부모 삭제 시 자식이 cascade 되지 않음.
- 디버깅 (Min): Apple Forums + Hacking with Swift 다수 보고. iOS 17.x 한정.
- 처방 1차 (실패): `inverse:` 제거 + `= []` 기본값 — 해결 안 됨.
- 처방 2차 (적용): `Watch.deleteCascade(in:)` 헬퍼로 자식을 명시적 삭제. 모든 프로덕션 삭제 경로는 이 헬퍼 통과 필수.
- 영향 레이어:
  - **Coder (Doyoon)**: WatchDetailView/CollectionView 의 watch 삭제 액션은 `deleteCascade(in:)` 호출.
  - **Reviewer (Jay)**: PR 리뷰에서 `context.delete(watch)` 직접 호출이 보이면 reject.
  - **Performance (Sora)**: 무브먼트별 측정이 수백 건 쌓일 수 있으니 일괄 삭제 시 transaction 분할 검토.

### 추가 셋업 메모
- `MovementDB.json`/`Localizable.strings`/`Assets.xcassets` 가 빌드 산출물에서 누락되는 문제 발견 → xcodegen `resources:` 키 대신 `sources:` 에 포함시켜 자동 분류로 해결.
- 테스트 타깃은 `GENERATE_INFOPLIST_FILE: YES` 필요 (Xcode 26.3 기본 동작 변경).
- 테스트는 `iPhone 15 Pro,OS=17.2` 와 `iPhone 17 Pro,OS=26.2` 양쪽에서 회귀 검증할 것.

### 다음 hand-off
- Week 2 진입. DSP 코어 (AudioCapture, 필터들, BPHEstimator, BeatDetector). DSP 모듈은 pure function 우선, fixture 없는 코드 머지 금지 (CLAUDE.md Hard Rule #1).
