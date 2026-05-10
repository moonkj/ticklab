# TickLab — Watch Accuracy Pro

iPhone으로 기계식 시계의 정확도를 측정하는 iOS 앱.

- Rate (초/일), Beat error (ms), Amplitude (°), BPH 측정
- 측정 신뢰도 0~100 score 제공
- 무브먼트 DB 기반 자동 매칭 + 코악시얼/스프링드라이브 안내
- 한국어/영어 1급 지원
- Phase 1 100% on-device

## Stack

- iOS 17+, SwiftUI, SwiftData
- AVFoundation + Accelerate(vDSP) — 오디오 캡처 및 DSP
- Charts — 트렌드
- SPM only

## Layout

```
WatchAccuracyPro/        # iOS app sources (xcodegen 생성 대상)
├── App/                 # @main + DI
├── Core/                # 비즈니스 로직 (DSP, Models, Movement, Time)
├── Features/            # 화면 단위 모듈
├── UI/                  # 공통 컴포넌트 + 테마
├── Resources/           # Asset catalog, MovementDB.json, Localizable.strings
└── Tests/
    ├── WatchAccuracyProTests/
    └── WatchAccuracyProUITests/

docs/
├── Watch_Accuracy_Pro_Master_Plan.md   # 단일 진실의 원천 (SSOT)
├── Watch_Accuracy_Pro_PRD.md
└── Watch_Accuracy_Pro_Claude_Code_Prompts.md

CLAUDE.md      # 프로젝트 메모리 (코딩 규칙·Hard Rules)
Tasklist.md    # 진행 추적 단일 문서
process.md     # 시간순 의사결정 로그
project.yml    # xcodegen 설정
```

## Build

```bash
# 1. Xcode 프로젝트 (재)생성
xcodegen

# 2. 빌드
xcodebuild -scheme WatchAccuracyPro \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build

# 3. 단위 테스트
xcodebuild test -scheme WatchAccuracyPro \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:WatchAccuracyProTests
```

## License

TBD (출시 전 결정)
