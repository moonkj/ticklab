import SwiftUI

/// 12-dot 시계 인덱스 ring — 브랜드 메타포(다이얼 인덱스).
/// 12개 dot 을 원형 배치하고, 12시 dot 만 골드로 강조할 수 있다.
/// `rotating` 시 아주 느린 회전(20s/회전). Reduce Motion 시 정적.
///
/// 사용처: 스플래시·온보딩·빈상태·공유카드의 브랜드 마크.
struct DotRingMark: View {
    var size: CGFloat = 80
    var rotating: Bool = false
    var goldTopDot: Bool = true
    /// 12시부터 시계방향으로 점등된 dot 개수(nil = 전체 점등). 스플래시 순차 점등용.
    var litCount: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    /// dot 지름은 ring 크기에 비례.
    private var dotDiameter: CGFloat { max(3, size * 0.075) }
    /// dot 중심이 놓일 반경.
    private var ringRadius: CGFloat { size / 2 - dotDiameter }

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                dot(at: i)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spin ? angle : 0))
        .onAppear {
            guard spin else { return }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
        .accessibilityHidden(true)
    }

    /// 실제 회전 여부 — rotating 옵션 && Reduce Motion 비활성.
    private var spin: Bool { rotating && !reduceMotion }

    @ViewBuilder
    private func dot(at index: Int) -> some View {
        // index 0 = 12시 위치(맨 위). 시계방향으로 배치.
        let theta = Double(index) / 12.0 * 2 * .pi - .pi / 2
        let x = CGFloat(CoreGraphics.cos(theta)) * ringRadius
        let y = CGFloat(CoreGraphics.sin(theta)) * ringRadius
        let isTop = index == 0
        let lit = litCount.map { index < $0 } ?? true

        Circle()
            .fill(isTop && goldTopDot
                  ? AnyShapeStyle(AppGradients.goldBrushed)
                  : AnyShapeStyle(AppColors.ink3.opacity(0.45)))
            .frame(width: isTop && goldTopDot ? dotDiameter * 1.25 : dotDiameter,
                   height: isTop && goldTopDot ? dotDiameter * 1.25 : dotDiameter)
            .opacity(lit ? 1 : 0.12)
            .offset(x: x, y: y)
    }
}

#Preview("DotRingMark") {
    VStack(spacing: 32) {
        DotRingMark(size: 120, rotating: true, goldTopDot: true)
        HStack(spacing: 24) {
            DotRingMark(size: 64, rotating: false, goldTopDot: true)
            DotRingMark(size: 64, rotating: false, goldTopDot: false)
        }
    }
    .padding(40)
    .background(AppColors.paper0)
}
