import SwiftUI

/// 골드 인장 — 성취 마크.
/// 구성: DotRingMark(정적) + 골드 hairline 링(trim 0→1 draw-on) + 중앙 SF Symbol.
/// 등장 시: hairline 이 0.5s 동안 그려지고, 미세 scale settle(0.92→1.0).
/// **Reduce Motion 시 즉시 완성형**(애니메이션 생략).
///
/// 사용처: A등급/COSC 통과/Wrapped 성취.
struct GoldSealView: View {
    var symbol: String = "checkmark"
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trim: CGFloat = 0
    @State private var scale: CGFloat = 1

    private var ringInset: CGFloat { size * 0.06 }

    var body: some View {
        ZStack {
            // 12-dot 인덱스 ring(브랜드 메타포) — 정적.
            DotRingMark(size: size, rotating: false, goldTopDot: true)

            // 골드 hairline 링 — draw-on 대상.
            Circle()
                .trim(from: 0, to: trim)
                .stroke(AppGradients.goldBrushed,
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.028), lineCap: .round))
                .frame(width: size - ringInset * 2, height: size - ringInset * 2)
                .rotationEffect(.degrees(-90))  // 12시에서 시작해 시계방향으로.

            // 중앙 심볼.
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(AppColors.accentDark)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .onAppear { animateIn() }
        .accessibilityHidden(true)
    }

    private func animateIn() {
        guard !reduceMotion else {
            trim = 1; scale = 1
            return
        }
        trim = 0
        scale = 0.92
        withAnimation(.easeInOut(duration: 0.5)) {
            trim = 1
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            scale = 1
        }
    }
}

#Preview("GoldSealView") {
    VStack(spacing: 32) {
        GoldSealView(symbol: "checkmark", size: 96)
        HStack(spacing: 24) {
            GoldSealView(symbol: "star.fill", size: 64)
            GoldSealView(symbol: "rosette", size: 64)
            GoldSealView(symbol: "trophy.fill", size: 64)
        }
    }
    .padding(40)
    .background(AppColors.paper0)
}
