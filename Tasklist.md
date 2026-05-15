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

- ✅ 4.1 공통 컴포넌트 (PrimaryButton, MetricBadge, HelpCard, ConfidenceBadge, WatchRowView, InfoPill)
- ✅ 4.2 `OnboardingView` (3페이지 swipe + CTA)
- ✅ 4.3 `ModeSelectView` (초보자/전문가 카드)
- ✅ 4.4 `CollectionView` (홈, 빈 상태 + 리스트, swipe-to-delete with deleteCascade)
- ✅ 4.5 `AddWatchView` + `MovementMatcher` 통합 (브랜드 picker + 모델 입력 + 자동 매칭 카드)
- ✅ 4.6 `WatchDetailView` (히어로 + 정보 카드 + 신뢰도 안내 + 측정 CTA + 이력)
- ✅ 4.7 SettingsView (모드/무음/Glossary 링크) + GlossaryView (7개 용어)
- ✅ 4.8 `UserPreferences` (@Observable + UserDefaults) — onboarding/모드/무음 기본
- ✅ 4.9 RootView 진입 분기 (onboarding → mode → collection)
- ✅ 4.10 Localizable 한국어/영어 60+ 키
- ✅ 4.11 Week 4 검증 (build PASS, 47/47 unit tests still PASS)

## Phase 1 — Week 5: Measurement (메인 화면)

Reference: Master Plan Part 7.2, Part 8

- ✅ 5.1 `MeasurementViewModel` (@Observable, idle→requesting→measuring→completed/failed 상태 머신)
- ✅ 5.2 `MeasurementView` (헤더 + 라이브 wave + metrics grid + confidence + 제어 버튼)
- ✅ 5.3 `LiveWaveformView` (TimelineView(.animation) 60fps Canvas)
- ✅ 5.4 무음 측정 모드 — `UIApplication.isIdleTimerDisabled` 토글
- ✅ 5.5 `MeasurementResultView` (초보자: 이모지 + 평가 / 전문가: 메트릭 grid + 메타데이터)
- ✅ 5.6 권한 거부 fallback — `HelpCard` + 설정 열기 버튼
- ✅ 5.7 SwiftData 저장 흐름 — `WatchMeasurement` 생성 + `watch.measurements` 자동 갱신
- ✅ 5.8 `WatchDetailView` 의 measure CTA 를 실제 `MeasurementView` 로 연결

## Phase 1 — Week 6: Polish + tests

- ✅ 6.1 `SettingsView` (Week 4 에 선행 구현)
- ✅ 6.2 `GlossaryView` 7개 용어 + 한/영 설명 (Week 4 에 선행 구현)
- ✅ 6.3 `TrendChartView` (SwiftUI Charts, 7d/30d 선택, confidence 가중 색상)
- ✅ 6.4 코악시얼 안내 카드 (`HelpCard` + `movement.reliability.coaxial.notice`) — WatchDetailView/MeasurementResultView 양쪽
- ✅ 6.5 권한 화면 카피 다듬기 — privacy 약속 명시
- ✅ 6.6 한/영 strings 검수 — 80+ 키, 키 누락 없음
- ✅ 6.7 UI 테스트 4개: smoke + 3개 메인 플로우 (onboarding → mode select, skip-to-collection, settings 진입)
- ✅ 6.8 베타 빌드 준비 — `MARKETING_VERSION 0.1.0`, Bundle ID `com.ticklab.watchaccuracypro`, NSMicrophoneUsageDescription 한국어 명시, `ITSAppUsesNonExemptEncryption: false`

## Phase 1 종료 검증

| 항목 | 상태 |
|---|---|
| 빌드 (iOS 17.2 sim) | ✅ |
| 빌드 (iOS 26.2 sim) | ✅ |
| 단위 테스트 47개 | ✅ |
| UI 테스트 4개 | ✅ |
| Hard Rule 위반 | 0건 |
| Phase 2/3 코드 임의 구현 | 0건 (모두 `// TODO(phase2):` 주석만) |

## Phase 1.5 — Hot-fix (Round 1 토론 결과 반영)

- ✅ DSPPipeline throttle 버그 수정 (`Int(elapsed * 2) % 1 == 0` 항상 참 → lastEmitTime 기반)
- ✅ waveformSamples 실제 갱신 경로 연결 (`liveWaveformStream` 신설 + ViewModel 구독)
- ✅ envelopeBuffer / rawBuffer 30초 ring trimming — 메모리 unbounded 방지
- ✅ AudioSource 주입 가능하도록 ViewModel 시그니처 확장 (테스트/preview 용)

## Phase 2 — Beta 기능 (사용자 승인 하 풀 구현)

Reference: Master Plan Part 12, Tasklist Phase 2 priority

- ✅ 2.1 `AtomicTimeService` (NTP UDP) — 첫 외부 호출. time.apple.com / pool.ntp.org 폴백. 4 신규 단위 테스트
- ✅ 2.2 `AudioInputManager` + AudioCapture BT/외부 입력 라우팅 — Settings 에서 입력 선택
- ✅ 2.3 `LongTestSession` SwiftData 모델 + `LongTestRunner` (foreground 자동 측정 + BGAppRefresh hook)
- ✅ 2.4 `DataExportService` (CSV/JSON) + Settings ShareLink 통합. CSV escape, JSON DTO
- ✅ 2.5 `MovementDBOTAService` (HTTPS + SHA-256 옵션 검증, App Support 캐시) + 무브먼트 DB Top 10 → Top 21
- ✅ 2.6 `MeasurementActivityAttributes` + `MeasurementLiveActivityService` (ActivityKit) — 잠금화면/Dynamic Island
- ✅ 2.7 Widget extension target (`WatchAccuracyProWidget`) — `LatestMeasurementWidget` + `MeasurementLiveActivityWidget`. App Group 통한 `SharedSnapshotStore` 공유
- ✅ 2.8 `BeatDetecting` 프로토콜 + `OnsetBeatDetector` + `CoreMLBeatDetector` (모델 부재 시 fall-back)

## Phase 3 — 동기화

- ✅ 3.1 SwiftData `cloudKitDatabase: .private(...)` 통한 CloudKit sync — `UserPreferences.iCloudSyncEnabled` 토글
- ✅ 3.2 Settings 의 iCloud 토글 + 자동 OTA 토글 (`UserPreferences.autoUpdateMovementDB`)

## Phase 2/3 검증

| 항목 | 상태 |
|---|---|
| 빌드 (iOS 17.2 sim) | ✅ |
| 단위 테스트 61개 (47 + 14 신규) | ✅ |
| UI 테스트 4개 | ✅ |
| Widget extension 빌드 | ✅ |
| Live Activity 코드 컴파일 | ✅ |
| CloudKit 컨테이너 옵션 | ✅ (시뮬레이터에서 entitlement 필요시 비활성) |

## Manual QA 필요 (실기기)

이 항목들은 시뮬레이터에서 검증 불가 — 실 iPhone + 실 시계로 Week 7 베타에서:
- [ ] `MeasurementView` 60fps 유지 (Instruments)
- [ ] `LiveWaveformView` 16ms frame budget
- [ ] 측정 정확도 ±2초/일 (Weishi 1900 비교)
- [ ] 메모리 200MB 이내
- [ ] 마이크 권한 거부 → fallback 흐름
- [ ] 무음 모드 (idleTimerDisabled) 동작
- [ ] 코악시얼 무브먼트 (Omega 8800)에서 amplitude 비표시 + 안내

### Phase 2/3 추가 Manual QA (Round 5 Sora 발의)
- [ ] 30분 연속 측정 — 배터리 5% 이하 소모 (Instruments Energy)
- [ ] Live Activity update rate — 1초 간격, Dynamic Island compact 갱신 부드러움
- [ ] OTA 적용 직후 첫 측정 — 새 무브먼트 lookup 일관성 (Min race 가드 검증)
- [ ] BT 헤드셋 연결 → 측정 도중 disconnect → fallback 라우팅
- [ ] LongTest 12시간 추적 — foreground 자동 측정 슬롯 누락 0건
- [ ] Widget Latest measurement — 측정 직후 위젯 갱신 시간 < 5초
- [ ] iCloud sync 켠 후 다른 디바이스에서 Watch 등장 (실 디바이스 2대)
- [ ] Export CSV 한국어 brand 명 (브레게, 까르띠에 등) 한글 인코딩 정상
- [ ] NTP 시간 비교 — 서버 미응답 시 timeout 정상 (3초 후)

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
