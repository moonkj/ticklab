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

---

## 2026-05-10 · Week 2 — DSP 코어 완료

### 산출물
- `AudioSource` 프로토콜 — 실 마이크와 합성 신호의 공통 추상화
- `AudioCapture` — AVAudioEngine `.measurement` 카테고리, 48kHz mono, 100ms 청크
- `PreEmphasisFilter` (1차 high-pass, stateful)
- `BandPassFilter` (Direct Form II Transposed biquad, 1k~10kHz)
- `EnvelopeExtractor` (vDSP abs + 1-pole IIR, 200Hz cutoff)
- `BPHEstimator` (autocorrelation, "최단 유의미 peak = inter-onset" 휴리스틱)
- `BeatDetector` (onset detection, refractory 30ms, tic/toc alternating parity)
- `SyntheticSignal.ticTocImpulseTrain` — 결정론적 tic-toc 시뮬레이터, beat error 시뮬 가능

### 검증
- ✅ 단위 테스트 27개 PASS on iOS 17.2 (filters 3개 + BPH 6개 + Beat 4개 + Model 4개 + Movement DB 5개 + Matcher 5개)
- ✅ 18000/21600/25200/28800/36000 BPH 모두 합성 신호에서 정확히 식별
- ✅ tic/toc parity가 28800 BPH에서 5초간 38~42 events 범위 내 검출, 인접 페어 alternating

### Cross-layer note (Hyemi)

**BPH 알고리즘 휴리스틱 변경 (Doyoon → Min 토론 결과)**
- 1차 시도: τ peak에서 candidate1=3600/τ, candidate2=7200/τ 둘 다 시도해 standard BPH 거리 짧은 쪽 채택. → 36000bph에서 실패 (full-cycle 200ms peak가 18000bph로 오해석되며 동률 처리 시 잘못된 픽).
- 2차 시도 (적용): "최단 유의미 peak (전역 최대의 50% 이상이고 local maximum) = inter-onset" 가설로 단일화. 18/19.8/21.6/25.2/28.8/36k 모두 통과.
- 실 시계는 합성 시뮬보다 noisy 하므로 Week 7 베타 단계에서 thresholdK·refractoryMs 등 hyperparam 재조정 가능성 있음 — 이때 fixture는 합성 + 실 .wav 양쪽으로 가져갈 것.

### 다음 hand-off
- Week 3 진입. RateCalculator, BeatErrorCalculator, AmplitudeEstimator, ConfidenceScorer, DSPPipeline 통합, SwiftData 저장 흐름. AmplitudeEstimator는 lift angle을 외부 주입받으며 코악시얼은 무조건 nil 반환.

---

## 2026-05-10 · Week 3 — DSP 메트릭 + 파이프라인 통합 완료

### 산출물
- `RateCalculator` — measuredBph/nominalBph로 초/일, beats 시퀀스에서 직접 산출하는 오버로드 두 가지
- `BeatErrorCalculator` — T1·T2 평균 차이의 절댓값, ms
- `AmplitudeEstimator` — lift_angle × T_beat / (π × t_imp) 공식, t_imp는 envelope FWHM 기반. swissLever 만 추정, 코악시얼/스프링드라이브는 nil
- `ConfidenceScorer` — SNR(30) + duration(25) + BPH conf(25) + beat sep(20) 가중합
- `MeasurementResult` / `LiveMetrics` 중간 모델
- `DSPPipeline` — AudioSource → 누적 envelope → analyze() 스냅샷 + AsyncStream<LiveMetrics> 라이브 스트림
- `SyntheticAudioSource` 테스트 픽스처 — DSPPipeline 통합 테스트가 마이크 없이 동작
- `Watch.deleteCascade(in:)` 헬퍼는 Week 1에서 도입, 이번 주 변경 없음

### 검증
- ✅ 47/47 unit tests PASS on iOS 17.2 (Filters 3 + BPH 6 + Beat 4 + Rate 5 + BeatError 3 + Amplitude 4 + Confidence 5 + Pipeline 3 + Model 4 + DB 5 + Matcher 5)
- ✅ 합성 28800/25200/28829 BPH 신호로 파이프라인 통합 검증
- ✅ 코악시얼 신호에서 amplitude nil + reliability note 키 자동 세팅

### Cross-layer note (Hyemi)

**AmplitudeEstimator 캘리브레이션 보류 (Sora·Jake 협의 필요)**
- 현재 알고리즘은 표준 호롤로지 공식 + envelope FWHM 으로 t_imp 근사. 합성 신호에서는 100~360° 클램프 범위로 떨어지지만 실측 정확도는 미검증.
- Week 7 베타 단계에서 Weishi 1900 ground truth 페어와 cross-validation 한 뒤 calibration 상수(tImp ↔ FWHM 비율) 조정 예정.
- **Coder(Doyoon)** 에게: Phase 1 안에서 알고리즘 변경 금지. 캘리브레이션은 hyperparam만 조정.
- **Reviewer(Jay)** 에게: AmplitudeEstimator 관련 PR 은 Week 7 이전엔 fixture 추가 외에는 reject.

**DSPPipeline `analyze()` 호출 비용**
- analyze() 가 매 라이브 스트림 emit 때마다 BPHEstimator/BeatDetector 를 envelope 전체에 대해 재실행. envelope 길이가 60초 → 2.88M 샘플 → autocorrelation O(N·lag) 부담.
- 현재 합성 신호 5초 기준 30초 가량 테스트 시간이 걸리며, 실시간 측정에서는 throttling 필요.
- **Performance(Sora)** 에게: Week 5 LiveWaveformView 작업 시 라이브 스트림 emit 주기를 1초 이상으로, 그리고 analyze() 도 마지막 N초 윈도우만 사용하도록 최적화 검토.

### 다음 hand-off
- Week 4 진입. UI 스캐폴드 — Onboarding, ModeSelect, Collection(Home), AddWatch, WatchDetail. 공통 컴포넌트(PrimaryButton, MetricBadge, ConfidenceBadge, HelpCard) 먼저 만들고 화면 단위로. 이번 주에는 측정 화면 X — 골격만 완성.

---

## 2026-05-10 · Phase 1 완료 — Week 4·5·6 통합 보고

### Week 4 — UI 스캐폴드
- 공통 컴포넌트 6개 (PrimaryButton, MetricBadge, ConfidenceBadge, HelpCard, WatchRowView, InfoPill)
- 5개 화면 + Settings/Glossary
- `UserPreferences` (UserDefaults backed @Observable)
- RootView 진입 분기

### Week 5 — 측정 화면
- `MeasurementViewModel` 상태 머신 (idle/requesting/measuring/completed/failed)
- `MeasurementView` + 60fps `LiveWaveformView` (TimelineView Canvas)
- `MeasurementResultView` 초보/전문가 분기
- 마이크 권한 + idle timer 토글 + SwiftData 저장 흐름

### Week 6 — 트렌드 + UI 테스트 + 폴리싱
- `TrendChartView` (SwiftUI Charts, confidence 기반 시각 가중)
- WatchDetailView 에 trend embed
- 4개 UI 테스트 시나리오 (smoke + onboarding 흐름 + 컬렉션 진입 + 설정 진입)
- 한/영 80+ 로컬라이제이션 키 검수

### 최종 검증
- ✅ build PASS on iOS 17.2 simulator (iPhone 15 Pro)
- ✅ 47 unit tests PASS (Models 4 + Movement DB 5 + Matcher 5 + Filters 3 + BPH 6 + Beat 4 + Rate 5 + BeatError 3 + Amplitude 4 + Confidence 5 + Pipeline 3)
- ✅ 4 UI tests PASS (Smoke + 3 main flows)
- ✅ Hard Rule 위반 0건
- ✅ Phase 2/3 hook 만 `// TODO(phase2):` 주석으로 남김 — 임의 구현 0건

### 남은 Manual QA (Week 7 베타)
- 60fps 측정 화면 검증 (Instruments)
- 메모리 200MB 이내 (Instruments leaks)
- DSP 정확도 검증 (Weishi 1900 ground truth, ±2초/일)
- 코악시얼 무브먼트 실측 (Omega 8800)
- 한/영 다국어 시뮬레이터 외 실 디바이스 화면 검수
- TestFlight 베타 업로드

### Phase 2 진입 시 우선순위
1. Bluetooth 외부 마이크 지원 — 정확도 보강
2. 데이터 export (CSV/JSON) — 워치메이커 페르소나 (김재철) 핵심 요구사항
3. Long test (12시간 추적) — 컬렉터 페르소나 (이재현)
4. 무브먼트 DB OTA 업데이트 — Top 30 확장

### 코드 통계 (커밋 기준)
- Swift 파일: 30+ (Core 16, Features 9, UI 6, App 3, Tests 11)
- Localizable 키: 한국어 80+ / 영어 80+ (paired)
- xcodegen `project.yml` 단일 진실 — `xcodegen` 한 번이면 .xcodeproj 재생성 가능
- 의존성: 0 (SPM, CocoaPods 없음 — Hard Rule #5 준수)
