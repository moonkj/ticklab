import SwiftUI

// MARK: - Launch bridge (cold-start splash)

/// 콜드스타트 1회 노출되는 ~0.6s 스플래시 — 12시 골드 dot 부터 순차 점등 후 메인으로 cross-fade.
/// 소리·햅틱 없음. Reduce Motion 시 즉시 표시 + 200ms fade-out.
/// `WatchAccuracyProApp` 가 in-memory flag 로 콜드스타트에서만 표시(웜 재진입 skip).
/// 브랜드 마크는 공유 기반층 `DotRingMark`(litCount 순차 점등) 사용.
struct LaunchBridgeView: View {
    /// 스플래시 종료(메인으로 전환) 콜백.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var litCount = 0
    @State private var glow = false
    @State private var titleOpacity: Double = 0

    /// dot 1개 점등 간격(초). 12 dots × interval ≈ 시퀀스 길이.
    private let dotInterval: Double = 0.042

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            // 은은한 골드 ambient glow.
            RadialGradient(
                colors: [AppColors.accent.opacity(glow ? 0.30 : 0.12), .clear],
                center: .center, startRadius: 0, endRadius: 220
            )
            .ignoresSafeArea()
            VStack(spacing: 30) {
                DotRingMark(
                    size: 132,
                    rotating: false,
                    goldTopDot: true,
                    litCount: reduceMotion ? nil : litCount
                )
                Text("TICKLAB")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(AppColors.accent.opacity(0.9))
                    .opacity(titleOpacity)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        guard !reduceMotion else {
            // 즉시 표시 + 200ms fade 후 종료.
            litCount = 12
            titleOpacity = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.2)) { onFinish() }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) { glow = true }
        // 12시 dot 부터 순차 점등.
        for i in 1...12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + dotInterval * Double(i)) {
                litCount = i
            }
        }
        // 워드마크 fade-in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 0.25)) { titleOpacity = 1 }
        }
        // 시퀀스 종료 → 메인으로 cross-fade.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            withAnimation(.easeInOut(duration: 0.28)) { onFinish() }
        }
    }
}

#Preview("Launch Bridge") {
    LaunchBridgeView(onFinish: {})
}
