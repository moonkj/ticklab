import SwiftUI

// MARK: - Launch bridge (cold-start splash)

/// 콜드스타트에 노출되는 스플래시 — 가운데 **"TL" 모노그램** + 둘레로 **회전하는 시계 dot 링** + 워드마크.
/// 처음 켤 때 충분히 보이도록 ~1.9s 유지 후 메인으로 cross-fade.
/// 소리·햅틱 없음. Reduce Motion 시 회전 없이 즉시 표시 + 짧은 fade-out.
/// `WatchAccuracyProApp` 가 in-memory flag 로 콜드스타트에서만 표시(웜 재진입 skip).
struct LaunchBridgeView: View {
    /// 스플래시 종료(메인으로 전환) 콜백.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0
    @State private var glow = false
    @State private var iconScale: CGFloat = 0.82
    @State private var titleOpacity: Double = 0

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            // 은은한 골드 ambient glow.
            RadialGradient(
                colors: [AppColors.accent.opacity(glow ? 0.34 : 0.12), .clear],
                center: .center, startRadius: 0, endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                ZStack {
                    // 회전하는 시계 dot 링 — 12시 골드 dot 이 둘레를 쓸고 돈다.
                    DotRingMark(size: 138, rotating: false, goldTopDot: true)
                        .rotationEffect(.degrees(spin))
                    // 가운데 "TL" 모노그램(골드 세리프). 앱 아이콘 대신 — 이미 아이콘 안에 dot 링이 있어 이중 방지.
                    Text("TL")
                        .font(.system(size: 48, weight: .semibold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.accentLight, AppColors.accent, AppColors.accentDark],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                        .scaleEffect(iconScale)
                }
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
            // 즉시 표시 + 400ms 후 종료.
            iconScale = 1; titleOpacity = 1; glow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.2)) { onFinish() }
            }
            return
        }
        // 링 회전 — 3.2s/회전(또렷하게).
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { spin = 360 }
        withAnimation(.easeInOut(duration: 0.7)) { glow = true }
        // 아이콘 spring 등장.
        withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { iconScale = 1 }
        // 워드마크 fade-in.
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) { titleOpacity = 1 }
        // 충분히 보여준 뒤(2.6s) 스르륵 디졸브로 메인 전환 — fade 0.6s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeInOut(duration: 0.6)) { onFinish() }
        }
    }
}

#Preview("Launch Bridge") {
    LaunchBridgeView(onFinish: {})
}
