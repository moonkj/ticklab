# TickLab — Watch Accuracy Pro · Tasklist

> 전체 진행상황 단일 추적 문서. 리더(아키텍트) 및 모든 팀원이 읽고 갱신.
> 상태 마커: ⬜ 대기 · 🟦 진행 · ✅ 완료 · ⚠️ 블락 · 🟥 실패

## 팀 구성

| 역할 | 코드네임 | 책임 |
|---|---|---|
| Lead / Architect | **Hyemi** (PM·UX·아키텍트) | 통합·최종 판단·process.md/Tasklist.md 갱신·git 커밋 |
| Coder | **Doyoon** (Teammate1) | Swift/SwiftUI/SwiftData/DSP 구현 |
| Debugger | **Min** (Teammate2) | 코드 검수, 가설 검증, 버그 분석 |
| Test Engineer / Reviewer | **Jay** (Teammate3) | 단위/UI 테스트, 최종 코드 리뷰 |
| Performance / Doc | **Sora** (Teammate4) | 60fps·메모리·배터리·문서화 |

> 운영 규칙
> - 한 PR 단위 = 한 task.
> - 버그 원인 불분명 시 Min과 다른 팀원이 서로 다른 가설을 제출하고 토론(과학적 토론).
> - 한 팀원의 변경이 다른 레이어(예: DSP→UI)에 영향이 있으면 Hyemi가 sync 노트를 process.md에 기록.

---

## Phase 0 — Bootstrap

- ✅ git init + remote 연결 (`https://github.com/moonkj/ticklab.git`)
- ✅ Tasklist.md / process.md / README.md / CLAUDE.md / .gitignore / project.yml
- ✅ Xcode 프로젝트 생성 (xcodegen)
- ✅ 초기 커밋 + push

## Phase 1 — Week 1: Project foundation + data models

Reference: Master Plan Part 6.2, Part 13.1

- ✅ 1.1 Xcode 프로젝트 (`WatchAccuracyPro.xcodeproj`) — xcodegen
- ✅ 1.2 디렉토리 스켈레톤 (Master Plan Part 6.2)
- ✅ 1.3 SwiftData `@Model`: `Watch`, `WatchMeasurement` (Foundation `Measurement<Unit>` 충돌로 리네임), `MeasurementMetadata`, `Position`
- ✅ 1.4 데이터 모델 단위 테스트 (init, 관계, cascade) — iOS 17 cascade 버그 회피용 `Watch.deleteCascade(in:)` 헬퍼 추가
- ✅ 1.5 `Movement` struct + `MovementDatabase` JSON loader
- ✅ 1.6 `MovementDB.json` seed (Top 10)
- ✅ 1.7 MovementDatabase 단위 테스트
- ✅ 1.8 `UI/Theme/Colors.swift`, `Typography.swift`
- ✅ 1.9 `ko.lproj/Localizable.strings`, `en.lproj/Localizable.strings`
- ✅ 1.10 `WatchAccuracyProApp.swift` + 빈 `ContentView`
- ✅ 1.11 Week 1 검증 (build PASS, 단위 테스트 14/14 PASS on iOS 17.2 + iOS 26.2)
- 🟦 1.12 Week 1 커밋

## Phase 1 — Week 2: DSP core

Reference: Master Plan Part 8.2

- ✅ 2.1 `AudioCapture` (AVAudioEngine, .measurement, 48kHz mono, 100ms 청크) + `AudioSource` 프로토콜
- ✅ 2.2 `PreEmphasisFilter`, `BandPassFilter` (Direct Form II Transposed biquad), `EnvelopeExtractor` (vDSP abs + 1-pole IIR)
- ✅ 2.3 `BPHEstimator` (autocorrelation, "최단 유의미 peak = inter-onset" 휴리스틱, 표준 BPH 스냅)
- ✅ 2.4 `BeatDetector` (onset + tic/toc parity, refractory 30ms)
- 🟦 2.5 `DSPPipeline` 골격 (`AsyncStream<DSPEvent>`) — Week 3에서 통합
- ✅ 2.6 합성 신호 fixture `SyntheticSignal.ticTocImpulseTrain` + DSP 단위 테스트 13개 추가 (총 27 PASS)
- ✅ 2.7 Week 2 검증 (27/27 PASS on iOS 17.2)

## Phase 1 — Week 3: DSP metrics + persistence

Reference: Master Plan Part 8.2, Part 6.3

- ✅ 3.1 `RateCalculator` (BPH 기반 + beat events 기반 두 진입점) + 5 테스트
- ✅ 3.2 `BeatErrorCalculator` (T1/T2 평균 차) + 3 테스트
- ✅ 3.3 `AmplitudeEstimator` (lift angle 주입, 코악시얼/스프링드라이브는 nil, FWHM 기반 t_imp 추정) + 4 테스트
- ✅ 3.4 `ConfidenceScorer` (SNR·시간·BPH·beat error 가중합) + 5 테스트
- ✅ 3.5 `DSPPipeline` 통합 — `LiveMetrics` AsyncStream + `analyze()` 스냅샷 + 3 통합 테스트
- 🟦 3.6 `MeasurementResult` → `WatchMeasurement` SwiftData 저장 매퍼 (Week 4 ViewModel 단계에서 wire-up)
- ✅ 3.7 신뢰도 라벨 적용 — `reliabilityLabel != .high` 면 amplitude nil + `reliabilityNoteKey` 부여
- ✅ 3.8 Week 3 검증 (47/47 PASS on iOS 17.2)

## Phase 1 — Week 4: UI scaffolds

Reference: Master Plan Part 7.2

- ⬜ 4.1 공통 컴포넌트 (PrimaryButton, MetricBadge, HelpCard, ConfidenceBadge)
- ⬜ 4.2 `OnboardingView`
- ⬜ 4.3 `ModeSelectView` (초보자/전문가)
- ⬜ 4.4 `CollectionView` (홈)
- ⬜ 4.5 `AddWatchView` + `MovementMatcher`
- ⬜ 4.6 `WatchDetailView`
- ⬜ 4.7 Localizable 키 채우기 + Preview 점검
- ⬜ 4.8 Week 4 검증 + 커밋

## Phase 1 — Week 5: Measurement (메인 화면)

Reference: Master Plan Part 7.2, Part 8

- ⬜ 5.1 `MeasurementViewModel` (@Observable)
- ⬜ 5.2 `MeasurementView`
- ⬜ 5.3 `LiveWaveformView` (Canvas, 60fps)
- ⬜ 5.4 무음 측정 모드
- ⬜ 5.5 `MeasurementResultView` (초보/전문가 분기)
- ⬜ 5.6 권한 거부 fallback
- ⬜ 5.7 Week 5 검증 + 커밋

## Phase 1 — Week 6: Polish + tests

- ⬜ 6.1 `SettingsView`
- ⬜ 6.2 `GlossaryView` (용어 7개)
- ⬜ 6.3 `TrendChartView` (SwiftUI Charts)
- ⬜ 6.4 코악시얼 안내 카드
- ⬜ 6.5 권한 화면 카피 다듬기
- ⬜ 6.6 한/영 strings 검수
- ⬜ 6.7 UI 테스트 3개 (메인 플로우)
- ⬜ 6.8 베타 빌드 메타데이터 + 커밋

---

## Hard Rules (CLAUDE.md에 동기화)

1. DSP 모듈 변경은 단위 테스트와 함께만
2. Phase 1 범위 외 기능 임의 추가 금지 (`// TODO(phase2):` 주석만)
3. 사용자 노출 문자열 인라인 금지 → Localizable.strings
4. 60fps 측정 화면, frame budget 16ms 초과 금지
5. CocoaPods/Carthage 금지 (SPM only)
6. 외부 API 호출 금지 (Phase 1은 100% on-device, 첫 외부 호출은 NTP)
7. `@Model` 스키마 변경 시 마이그레이션 명시
8. 측정/사진 데이터 외부 전송 금지
9. 신뢰도 라벨 무시 금지
10. 테스트 없는 PR 머지 금지 (DSP·Model·ViewModel 필수)
