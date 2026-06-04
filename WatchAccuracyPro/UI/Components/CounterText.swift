import SwiftUI

/// 0 → 목표값 카운트업 텍스트.
/// - `monospacedDigit()` 필수(자릿수 변동 시 가로 점프 방지).
/// - iOS17 `.contentTransition(.numericText())` + `withAnimation` 으로 숫자 롤링.
/// - **Reduce Motion 시 즉시 최종값**(애니메이션 생략).
///
/// 사용처: 측정 결과 메트릭, Wrapped(연말정리) 성취 숫자.
struct CounterText: View {
    let value: Double
    var format: String = "%.1f"
    var duration: Double = 0.8
    var font: Font

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Double = 0
    @State private var didStart = false

    var body: some View {
        Text(String(format: format, displayed))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: displayed))
            .onAppear { start() }
            // 외부에서 value 가 바뀌면 다시 카운트업.
            .onChange(of: value) { _, _ in restart() }
            .accessibilityLabel(Text(String(format: format, value)))
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        guard !reduceMotion else { displayed = value; return }
        // 0에서 시작 → 목표값까지 단일 애니메이션. numericText 가 자릿수 롤링을 담당.
        displayed = 0
        withAnimation(.easeOut(duration: duration)) {
            displayed = value
        }
    }

    private func restart() {
        guard !reduceMotion else { displayed = value; return }
        withAnimation(.easeOut(duration: duration)) {
            displayed = value
        }
    }
}

#Preview("CounterText") {
    VStack(spacing: 24) {
        CounterText(value: 1.8, format: "%+.1f",
                    font: AppTypography.monoMetricLarge)
            .foregroundStyle(AppColors.ink0)
        CounterText(value: 287, format: "%.0f", duration: 1.0,
                    font: AppTypography.monoMetric)
            .foregroundStyle(AppColors.accentDark)
        CounterText(value: 99.2, format: "%.1f%%",
                    font: AppTypography.monoMetric)
            .foregroundStyle(AppColors.success)
    }
    .padding(40)
    .background(AppColors.paper0)
}
