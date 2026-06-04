import SwiftUI

// MARK: - Brand foundation primitives
//
// 웨이브2-D 가 소비하는 브랜드 기반층. (DotRingMark · CounterText · GoldSealView ·
// AppGradients.goldFoil · View.luxeCard()). 디자인 기반 wave 의 산출물을 본 worktree HEAD
// 에서 찾을 수 없어, 마감/와우 연출이 의존하는 최소 표면을 여기 정의한다.
// 의도적으로 순수 SwiftUI · side-effect 無 · @Model/네트워크 무의존이라 추후 TickLabUI 로 이관 가능.

/// 12-dot 시계 인덱스 브랜드 마크. 12시 위치 dot 을 골드로 강조한다.
/// - `size`: 마크 한 변 길이.
/// - `rotating`: true 면 아주 느린 회전(브랜드 와우). Reduce Motion 시 자동 정지.
/// - `goldTopDot`: 12시 dot 골드 강조 여부.
/// - `litCount`: 12시부터 시계방향으로 점등된 dot 개수(`nil` = 전체 점등). 스플래시 시퀀스용.
struct DotRingMark: View {
    var size: CGFloat = 100
    var rotating: Bool = false
    var goldTopDot: Bool = true
    var litCount: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    private var dotRadius: CGFloat { size * 0.38 }

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                dot(at: i)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .onAppear {
            guard rotating, !reduceMotion else { return }
            withAnimation(.linear(duration: 36).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }

    @ViewBuilder
    private func dot(at i: Int) -> some View {
        let radians = (Double(i) * 30 - 90) * .pi / 180
        let isTop = i == 0 && goldTopDot
        let base = size * (isTop ? 0.052 : 0.032)
        let lit: Bool = {
            guard let n = litCount else { return true }
            return i < n
        }()
        Circle()
            .fill(isTop ? AppColors.accent : Color.white.opacity(0.7))
            .frame(width: base, height: base)
            .opacity(lit ? 1 : 0.12)
            .offset(x: dotRadius * cos(radians), y: dotRadius * sin(radians))
    }
}

/// 숫자 카운트업 텍스트 — 0(또는 from)에서 value 까지 부드럽게 증가.
/// Reduce Motion 시 즉시 최종값. monospaced 숫자 정렬(타이포 SSOT) 유지.
struct CounterText: View {
    let value: Double
    var from: Double = 0
    var duration: Double = 1.1
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var font: Font = .system(size: 76, weight: .black, design: .monospaced)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0
    @State private var started = false

    var body: some View {
        Text(format(reduceMotion ? value : animated))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear {
                guard !started else { return }
                started = true
                animated = from
                guard !reduceMotion else { animated = value; return }
                withAnimation(.easeOut(duration: duration)) {
                    animated = value
                }
            }
    }
}

/// 골드 인장 — DotRingMark 미니 + 자간확대 "TICKLAB". 공유카드/마감 화면 서명용.
/// "TICKLAB" 은 브랜드 고정 텍스트(현지화 불필요).
struct GoldSealView: View {
    var markSize: CGFloat = 18
    var fontSize: CGFloat = 11
    var tint: Color = .white.opacity(0.6)

    var body: some View {
        HStack(spacing: markSize * 0.42) {
            DotRingMark(size: markSize, rotating: false, goldTopDot: true)
            Text("TICKLAB")
                .font(.system(size: fontSize, weight: .semibold))
                .tracking(fontSize * 0.32)
        }
        .foregroundStyle(tint)
    }
}

/// 브랜드 그라데이션 모음.
enum AppGradients {
    /// 골드 포일 — engraving/인장 hairline·강조 underline 에 쓰는 따뜻한 금색 띠.
    static let goldFoil = LinearGradient(
        colors: [
            AppColors.accentLight,
            AppColors.accent,
            AppColors.accentDark,
            AppColors.accent
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// 럭셔리 카드 컨테이너 — paper1 + 얇은 rule + 부드러운 그림자.
private struct LuxeCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.rule, lineWidth: 1)
            )
            .cardShadow(.mid)
    }
}

extension View {
    /// 럭셔리 카드 스타일(여백·둥근 모서리·hairline·그림자).
    func luxeCard(padding: CGFloat = 20, cornerRadius: CGFloat = AppRadius.xl) -> some View {
        modifier(LuxeCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Launch bridge (cold-start splash)

/// 콜드스타트 1회 노출되는 ~0.6s 스플래시 — 12시 골드 dot 부터 순차 점등 후 메인으로 cross-fade.
/// 소리·햅틱 없음. Reduce Motion 시 즉시 표시 + 200ms fade-out.
/// `WatchAccuracyProApp` 가 in-memory flag 로 콜드스타트에서만 표시(웜 재진입 skip).
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

#Preview("Dot Ring") {
    DotRingMark(size: 140, rotating: true, goldTopDot: true)
        .padding()
        .background(AppColors.primaryDeep)
}

#Preview("Gold Seal") {
    GoldSealView()
        .padding()
        .background(AppColors.primaryDeep)
}
