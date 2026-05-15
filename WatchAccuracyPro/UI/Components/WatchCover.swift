import SwiftUI

/// 디자인 mockup 의 generated artwork — 시계 dial 일러스트.
/// 시계의 brand 시그너처 색으로 그라디언트 + 시침/분침/초침 + 12 시간 마커.
struct WatchCover: View {
    enum Size { case sm, md, lg, xl }

    let watch: Watch
    let size: Size
    var showLabel: Bool = false

    /// 색상 — 브랜드별 시그너처. 미등록 브랜드는 짙은 인디고 + 골드 폴백.
    private var coverColors: (from: Color, to: Color, accent: Color) {
        let palettes: [String: (Color, Color, Color)] = [
            "Tudor":     (Color(red: 0.04, green: 0.12, blue: 0.18),
                          Color(red: 0.08, green: 0.23, blue: 0.35),
                          Color(red: 0.62, green: 0.72, blue: 0.80)),
            "Omega":     (Color(red: 0.05, green: 0.16, blue: 0.12),
                          Color(red: 0.11, green: 0.28, blue: 0.20),
                          Color(red: 0.64, green: 0.69, blue: 0.56)),
            "Rolex":     (Color(red: 0.10, green: 0.10, blue: 0.10),
                          Color(red: 0.20, green: 0.20, blue: 0.20),
                          Color(red: 0.83, green: 0.69, blue: 0.42)),
            "Hamilton":  (Color(red: 0.16, green: 0.15, blue: 0.09),
                          Color(red: 0.29, green: 0.26, blue: 0.15),
                          Color(red: 0.79, green: 0.70, blue: 0.48)),
            "Grand Seiko": (Color(red: 0.11, green: 0.14, blue: 0.16),
                            Color(red: 0.23, green: 0.28, blue: 0.33),
                            Color(red: 0.89, green: 0.89, blue: 0.89)),
        ]
        if let p = palettes[watch.brand] {
            return (from: p.0, to: p.1, accent: p.2)
        }
        return (
            from:   Color(red: 0.11, green: 0.12, blue: 0.16),
            to:     Color(red: 0.17, green: 0.20, blue: 0.29),
            accent: Color(red: 0.78, green: 0.70, blue: 0.48)
        )
    }

    /// size 별 카드 height (sm 은 부모가 정해 줌).
    private var coverHeight: CGFloat? {
        switch size {
        case .sm: return nil
        case .md: return 120
        case .lg: return 240
        case .xl: return 320
        }
    }

    var body: some View {
        let c = coverColors
        let content = ZStack {
            // 배경 그라디언트 — 카드 전체 채움
            LinearGradient(
                colors: [c.from, c.to],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 다이얼 — GeometryReader 로 카드 크기 받아서 비율 계산
            GeometryReader { geo in
                let dialSize = min(geo.size.width, geo.size.height) * (size == .sm ? 0.78 : 0.62)
                DialIllustration(diameter: dialSize, accent: c.accent)
                    .frame(width: dialSize, height: dialSize)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }

            // brand 라벨 (top-left, italic serif) + AUTOMATIC (bottom-right)
            if showLabel {
                VStack {
                    HStack {
                        Text(watch.brand)
                            .font(.system(size: 10, weight: .regular, design: .serif).italic())
                            .tracking(2)
                            .foregroundStyle(c.accent.opacity(0.7))
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Text("AUTOMATIC")
                            .font(.system(size: 8, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(c.accent.opacity(0.5))
                    }
                }
                .padding(14)
            }
        }

        return Group {
            if size == .sm {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: coverHeight)
            }
        }
    }
}

/// 다이얼 일러스트 — 12 시간 마커 + 시침/분침/초침 + 중앙 cap.
private struct DialIllustration: View {
    let diameter: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            // 외곽 원
            Circle()
                .fill(Color.black.opacity(0.25))
                .overlay(Circle().stroke(accent.opacity(0.5), lineWidth: 1.2))

            // 내측 그라디언트 음영
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.15), Color.black.opacity(0.4)],
                        center: UnitPoint(x: 0.5, y: 0.4),
                        startRadius: 0,
                        endRadius: diameter * 0.5
                    )
                )
                .padding(diameter * 0.05)

            // 12 시간 마커
            ForEach(0..<12, id: \.self) { i in
                let isMain = i % 3 == 0
                Rectangle()
                    .fill(accent)
                    .opacity(isMain ? 0.95 : 0.55)
                    .frame(
                        width: isMain ? max(2, diameter * 0.018) : max(1, diameter * 0.008),
                        height: isMain ? diameter * 0.07 : diameter * 0.04
                    )
                    .offset(y: -diameter / 2 + (isMain ? diameter * 0.07 : diameter * 0.05))
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // 시침 (10:10 — −60°)
            Capsule()
                .fill(accent)
                .frame(width: max(2, diameter * 0.020), height: diameter * 0.32)
                .offset(y: -diameter * 0.16)
                .rotationEffect(.degrees(-60))

            // 분침 (10:10 — +60°)
            Capsule()
                .fill(accent)
                .frame(width: max(1.5, diameter * 0.014), height: diameter * 0.42)
                .offset(y: -diameter * 0.21)
                .rotationEffect(.degrees(60))

            // 초침 (붉은 점)
            Capsule()
                .fill(Color(red: 0.81, green: 0.32, blue: 0.24))
                .frame(width: max(1, diameter * 0.008), height: diameter * 0.48)
                .offset(y: diameter * 0.05)
                .rotationEffect(.degrees(180))

            // 중앙 cap
            Circle()
                .fill(accent)
                .frame(width: max(4, diameter * 0.04), height: max(4, diameter * 0.04))
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        WatchCover(watch: Watch(brand: "Tudor", model: "Black Bay 58"), size: .xl, showLabel: true)
        HStack(spacing: 12) {
            WatchCover(watch: Watch(brand: "Omega", model: "Seamaster"), size: .sm)
                .frame(width: 76, height: 76)
            WatchCover(watch: Watch(brand: "Rolex", model: "Submariner"), size: .sm)
                .frame(width: 76, height: 76)
            WatchCover(watch: Watch(brand: "Grand Seiko", model: "Snowflake"), size: .sm)
                .frame(width: 76, height: 76)
        }
    }
    .padding()
    .background(AppColors.paper0)
}
