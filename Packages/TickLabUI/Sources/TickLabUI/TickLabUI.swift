// TickLabUI — 디자인 시스템 패키지 진입점.
//
// 현재 단계: 패키지 구조 확립.
// 향후 이관 예정 컴포넌트:
//   - AppColors, AppRadius (Colors.swift)
//   - PrimaryButton, PressableCard, EmptyState
//   - Chip, Sparkline, ConfidenceBadge
//   - SkeletonView, AnimatedEmptyIcon
//
// 이관 조건: @Model, modelContext, UserPreferences 의존성 제거 완료 시.
// 현재는 앱 모듈에서 직접 import 하므로 이 파일은 placeholder.

public enum TickLabUIVersion {
    public static let current = "1.1.0"
}
