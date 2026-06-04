# TickLab — Watch Accuracy Pro · Project Memory

## What this project is

iOS 앱. **"내 시계와 함께하는 모든 순간을 기록·관리·분석·공유하는 시계 라이프 플랫폼"**. 기계식 시계 정확도 측정에서 출발했지만 지금은 아래 5개 축을 **동등하게** 다룬다 — 측정 전용 앱이 아니다([[project_app_identity]]).

1. **측정·진단** — iPhone 마이크로 rate·beat error·amplitude 측정 + AI 해석 + 신뢰도 등급 + 폰 클록 보정.
2. **컬렉션 관리** — 시계별 스펙·사진·시리얼·구매가/재무, 오버홀·정비 알림.
3. **생활 기록** — 착용 기록·일기·추억/하이라이트·이벤트 태그·무드.
4. **분석** — 주간/월간/연간 트렌드·착용 heatmap·Wrapped(연말정리)·브랜드 리그(글로벌 랭킹).
5. **커뮤니티(17+ UGC)** — 익명 사진 피드·좋아요/댓글/팔로우·뱃지·신고/차단.

타깃: 컬렉터·입문자·워치메이커. 가격: **월간·연간 Pro 구독**(무료 티어 + Pro). 데이터는 **기본 on-device**(SwiftData), 외부 전송은 사용자 주도 커뮤니티/피드백/브랜드리그 옵트인에 한정. 브랜드: TickLab.

상세 PRD·아키텍처·DSP 명세는 `docs/Watch_Accuracy_Pro_Master_Plan.md`. 단일 진실의 원천(SSOT).

## Stack

- iOS 17+ (Live Activity, SwiftData 활용)
- SwiftUI (UI), SwiftData (저장), AVFoundation + Accelerate/vDSP (DSP)
- CoreML (Phase 2 베타부터)
- Charts (트렌드 그래프), WidgetKit + ActivityKit (Phase 2)
- 테스트: XCTest, ViewInspector (필요시)
- 의존성 관리: SPM only (CocoaPods 금지)
- 최소 지원: iOS 17.0, iPhone 11+
- Bundle ID: `com.ticklab.watchaccuracypro`

## Coding Conventions

### Swift Style
- Swift API Design Guidelines 준수
- 들여쓰기: 4 spaces
- 줄 길이: 120자 권장, 140자 hard limit
- 파일 헤더 주석 없음 (Xcode 자동 생성된 것 삭제)
- `// MARK: -` 으로 섹션 구분
- 한국어 주석 OK, 변수/함수/타입명은 영문

### SwiftUI 패턴
- View는 작게 쪼개라 (한 view 200줄 넘으면 분리)
- `@State` 는 view 로컬 상태만, 비즈니스 로직은 `@Observable` ViewModel로
- ViewModel은 `Features/{Name}/` 안에 `{Name}ViewModel.swift`
- Preview 매크로 (`#Preview`) 모든 view에 필수

### SwiftData
- `@Model` 은 `Core/Models/` 안에만 둠
- `ModelContext` 는 view 에서 `@Environment(\.modelContext)` 로 주입
- Migration 필요한 변경은 PR description에 명시
- **iOS 17 cascade delete 버그**: `@Relationship(.cascade)` 가 명시적 `save()` 후 자식을 cascade 하지 않는 알려진 버그가 있음. `Watch` 삭제 시 반드시 `watch.deleteCascade(in: context)` 헬퍼 사용 (Core/Models/WatchDeletion.swift). 직접 `context.delete(watch)` 호출 금지.

### DSP 코드
- 모든 DSP 모듈은 pure function으로 (가능한 한)
- 입력은 `[Float]` 또는 `UnsafeBufferPointer<Float>`, 출력은 명시적 struct
- Side effect 없음 (오디오 캡처만 예외)
- 테스트 fixture 없으면 머지 금지

### Localization
- 사용자 노출 문자열 100% `Localizable.strings`
- 키 네이밍: `screen.section.purpose` (예: `measurement.button.start`)
- `String(localized: "key")` 사용
- 한국어가 default (`ko.lproj/Localizable.strings`)

## Build & Test

```bash
# 빌드
xcodebuild -scheme WatchAccuracyPro -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# 단위 테스트
xcodebuild test -scheme WatchAccuracyPro -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:WatchAccuracyProTests

# UI 테스트
xcodebuild test -scheme WatchAccuracyPro -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:WatchAccuracyProUITests
```

매 작업 끝에 빌드 + 단위 테스트 통과 확인. 실패 상태로 머지 금지.

## Directory Layout

`docs/Watch_Accuracy_Pro_Master_Plan.md` Part 6.2 참고. 이 구조 변경하지 말 것. 새 폴더 추가가 필요하면 먼저 PR 코멘트에서 합의.

## Hard Rules — 절대 어기지 말 것

1. **DSP 모듈 변경은 단위 테스트와 함께만** — fixture 없이 변경 금지
2. **Phase 1 범위 외 기능 임의 추가 금지** — Phase 2/3 코드는 `// TODO(phase2):` 주석만 남기고 구현 X
3. **사용자 노출 문자열 인라인 금지** — 무조건 Localizable.strings
4. **60fps 측정 화면** — `MeasurementView`/`LiveWaveformView` 의 frame budget 16ms 초과 금지. 초과 시 PR description에 사유 명시
5. **CocoaPods/Carthage 사용 금지** — SPM only
6. **외부 API 호출 추가 시 사전 합의** — Phase 1은 100% on-device. 첫 외부 호출은 atomic time NTP 한 군데뿐
7. **`@Model` 스키마 변경 시 마이그레이션 명시** — SwiftData lightweight migration 가능 범위 확인하고 진행
8. **사진/측정 데이터 외부 전송 금지** — 기본은 on-device. CloudKit는 Phase 3. **(2026-05-31 개정·개발자 승인)** 예외: 사용자가 **명시적으로 게시 버튼을 눌러 공유한 커뮤니티 사진 1장**에 한해 외부 전송 허용. 단 ⓐ EXIF strip 강제 ⓑ 측정 데이터(rate/amplitude/beat error)·시리얼·구매가는 여전히 전송 절대 금지 ⓒ per-photo 명시 동의. 자동/일괄 업로드 금지. 자세한 범위는 `docs/community/PLAN.md`. **(2026-06-01 개발자 승인)** 별도 예외: 사용자가 직접 '공유' 버튼으로 만드는 **결과 공유카드 이미지**(`ShareCardComposerView`, `show metrics` 토글)에는 rate/confidence 등 측정값 표시 허용 — 본인 기기 산출물의 사용자 주도 공유(스크린샷급)이며 위 **커뮤니티(Supabase 업로드) 경로와 별개**다. 커뮤니티 업로드에는 측정 데이터 전송 금지 원칙 유지. **(2026-06-03 개정·개발자 승인)** 위 '커뮤니티 업로드 측정 데이터 금지' 원칙 완화: 사용자가 `ShareCardComposerView` 의 **'커뮤니티에 등록' 버튼을 직접 눌러** 게시하는 경우, 카드에 표시된 측정값(rate/confidence 등)이 **이미지 픽셀로 함께** 커뮤니티에 게시되는 것을 허용한다 — 본인 결과의 사용자 주도 1장 게시(스크린샷급, 게시 버튼 = per-post 명시 동의). 단 ⓐ EXIF strip·온디바이스 이미지검열·하루1장·EULA 게이트 그대로 적용 ⓑ 시리얼·구매가는 여전히 전송 금지 ⓒ 자동/일괄 금지 ⓓ **구조적 측정 데이터(별도 컬럼/JSON 필드) 전송은 여전히 금지** — 어디까지나 사용자가 만든 공유카드 이미지 1장에 한함.
9. **신뢰도 라벨 무시 금지** — 무브먼트 DB의 `confidenceLabel` 이 `medium`/`low` 인 캘리버는 amplitude 노출 X, 안내 카드 표시 O
10. **테스트 없는 PR 머지 금지** (DSP·Model·ViewModel은 필수)

## Naming

- ViewModel: `{Feature}ViewModel`
- View: `{Feature}View`, `{Feature}{Subview}View`
- Service: `{Domain}Service` (예: `AtomicTimeService`)
- Repository: `{Entity}Repository` (필요시)
- Use Case (있으면): `{Action}{Entity}UseCase`
- 테스트: `{Type}Tests`

## Phase Hooks

Phase 1 코드 안에 Phase 2/3 hook을 남길 때:
```swift
// TODO(phase2): Bluetooth 외부 마이크 지원
// TODO(phase3): CloudKit 동기화
```
구현은 절대 X. 단지 어디에 들어갈지 표시만.

## Community (Phase 2 — 2026-05-31 착수, 개발자 승인)

익명 사진 피드 + 좋아요. 측정 전용 아님([[project_app_identity]]) — 생활기록 플랫폼의 커뮤니티 축. SSOT: `docs/community/PLAN.md`.

- **익명**: 화면에 닉네임/실명 비노출. 단 검열·차단·소유권용 **내부 안정 ID 필수**(Supabase Anonymous Auth, 차단 우회 방지). 게시는 익명 표시.
- **하루 1장** 게시 제한. 좋아요·열람은 (콜드스타트 단계엔) 무료.
- **게이팅(밀도 확보 후 ON)**: 무료=최근 ~10장 풀 노출 + 인기글 부분 흐림 + "Pro로 전체 보기" CTA. 본인 글·하루 1장 업로드·좋아요는 영속 무료. 흐림 클릭베이트 금지(앱스토어 4.0/2.3).
- **검열**: 온디바이스 사전필터(SensitiveContentAnalysis) + 신고기반 자동 숨김. 외부 vision API 미사용(비용·#6).
- **UGC 필수(없으면 리젝, Guideline 1.2)**: 신고·차단·콘텐츠필터·zero-tolerance EULA·24h 조치·연락처. 17+ 등급.
- 외부 호출은 Supabase(기존 합의 baseURL)만. 새 테이블/Storage/Auth는 `docs/community/schema.sql`.
- `FeatureFlags.communityEnabled` 로 게이트. 백엔드 배포 전까지 OFF.

## Team & Process

- 리더(Hyemi)가 통합·아키텍처·UX·git 커밋·process.md 갱신
- Coder(Doyoon) 구현, Debugger(Min) 검수, Reviewer(Jay) 테스트·리뷰, Performance(Sora) 60fps/메모리 검증
- 버그 원인 불분명 시 다른 가설을 가진 두 팀원이 토론 후 결론
- 한 레이어 변경이 다른 레이어 영향 시 process.md에 cross-layer note

## When in doubt

1. MasterPlan의 해당 Part 다시 읽기
2. 그래도 모호하면 코드 작성 전에 사용자(개발자)에게 질문
3. 가정을 명시하고 진행할 거면 PR description에 "Assumption:" 으로 명기

## Don't

- "더 좋은 방법" 이라며 디렉토리 구조 임의 변경
- React 패턴 가져오기 (이건 Swift/SwiftUI 프로젝트)
- 의존성 새로 추가할 때 동의 없이 진행
- TestFlight·App Store 관련 설정 임의 변경
