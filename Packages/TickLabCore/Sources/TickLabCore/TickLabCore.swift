// TickLabCore — DSP·측정 알고리즘 패키지 진입점.
//
// 현재 단계: 패키지 구조 확립.
// 향후 이관 예정 모듈:
//   - BPHEstimator, BeatDetector (DSP — 순수 함수)
//   - RateCalculator, BeatErrorCalculator
//   - MovementDatabase (static JSON, @Model 없음)
//   - DialColorExtractor, WatchPhotoProcessor
//   - ServiceCenterFavoritesService
//   - WatchModelSuggestionService
//
// 이관 조건: SwiftUI, SwiftData import 제거 확인 후 파일 이동.
// 현재는 앱 모듈에서 직접 컴파일 — 이 파일은 placeholder.

public enum TickLabCoreVersion {
    public static let current = "1.0.0"
}
