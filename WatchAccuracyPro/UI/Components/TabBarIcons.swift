import SwiftUI
import UIKit

// MARK: - Custom tab bar icons
//
// 시스템 TabView 의 .tabItem 은 Image+Text 만 렌더하므로, 커스텀 벡터 아이콘을
// ImageRenderer 로 template UIImage 로 래스터화해 사용한다(탭바가 선택/비선택 색으로 tint).
// 모노라인 톤은 WatchIcons/BadgeGlyphs 와 통일.

/// 탭별 커스텀 아이콘 template UIImage (1회 렌더 후 캐시).
/// ImageRenderer 가 main-actor 격리라 enum 전체를 @MainActor 로(뷰 body 에서만 접근).
@MainActor
enum TabBarIcons {
    static let collection = render(CollectionTabIcon())
    static let today      = render(TodayTabIcon())
    static let journal    = render(JournalTabIcon())
    static let stats      = render(StatsTabIcon())
    static let community  = render(CommunityTabIcon())

    /// SwiftUI 아이콘 뷰 → alwaysTemplate UIImage(@3x).
    private static func render<V: View>(_ icon: V) -> UIImage {
        let renderer = ImageRenderer(content: icon.frame(width: 30, height: 30))
        renderer.scale = 3
        let img = renderer.uiImage ?? UIImage()
        return img.withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - Icon views (black on clear → 템플릿 tint)

/// 컬렉션 — 2×2 미니 다이얼 그리드.
private struct CollectionTabIcon: View {
    var size: CGFloat = 26
    private var lw: CGFloat { size * 0.072 }
    private var d: CGFloat { size * 0.4 }
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let col = CGFloat(i % 2), row = CGFloat(i / 2)
                Circle().stroke(Color.black, lineWidth: lw)
                    .overlay(Circle().fill(Color.black).frame(width: d * 0.2, height: d * 0.2))
                    .frame(width: d, height: d)
                    .offset(x: col * size * 0.46 - size * 0.23,
                            y: row * size * 0.46 - size * 0.23)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 오늘 — 다이얼 + 시·분침(지금).
private struct TodayTabIcon: View {
    var size: CGFloat = 26
    private var lw: CGFloat { size * 0.075 }
    var body: some View {
        ZStack {
            Circle().stroke(Color.black, lineWidth: lw).frame(width: size * 0.86, height: size * 0.86)
            // 분침
            Capsule().fill(Color.black).frame(width: lw * 0.9, height: size * 0.30)
                .offset(y: -size * 0.1).rotationEffect(.degrees(35))
            // 시침
            Capsule().fill(Color.black).frame(width: lw, height: size * 0.20)
                .offset(y: -size * 0.05).rotationEffect(.degrees(-65))
            Circle().fill(Color.black).frame(width: size * 0.1, height: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}

/// 저널 — 책(표지 + 스파인 + 텍스트 라인).
private struct JournalTabIcon: View {
    var size: CGFloat = 26
    private var lw: CGFloat { size * 0.072 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .stroke(Color.black, lineWidth: lw)
                .frame(width: size * 0.64, height: size * 0.82)
            // 스파인
            Rectangle().fill(Color.black).frame(width: lw, height: size * 0.82)
                .offset(x: -size * 0.16)
            // 텍스트 라인 2줄
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(Color.black).frame(width: size * 0.24, height: lw * 0.8)
                    .offset(x: size * 0.06, y: CGFloat(i) * size * 0.16 - size * 0.06)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 통계 — 증가하는 막대 3개 + 베이스라인.
private struct StatsTabIcon: View {
    var size: CGFloat = 26
    private var lw: CGFloat { size * 0.075 }
    private let heights: [CGFloat] = [0.42, 0.64, 0.88]
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: size * 0.1) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Color.black)
                        .frame(width: size * 0.16, height: size * heights[i])
                }
            }
            .frame(height: size * 0.88, alignment: .bottom)
            Rectangle().fill(Color.black).frame(width: size * 0.8, height: lw * 0.8)
                .offset(y: lw)
        }
        .frame(width: size, height: size)
    }
}

/// 커뮤니티 — 인물 2.
private struct CommunityTabIcon: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            person.scaleEffect(0.85).offset(x: size * 0.2, y: size * 0.05)
            person.offset(x: -size * 0.13)
        }
        // 인물은 시각 무게가 위쪽이라 살짝 내려 다른 탭 아이콘과 수직 정렬.
        .offset(y: size * 0.08)
        .frame(width: size, height: size)
    }
}

private extension CommunityTabIcon {
    var person: some View {
        VStack(spacing: -size * 0.03) {
            Circle().fill(Color.black).frame(width: size * 0.34, height: size * 0.34)
            // 어깨 — 반원
            Circle().fill(Color.black)
                .frame(width: size * 0.58, height: size * 0.58)
                .mask(Rectangle().frame(width: size * 0.58, height: size * 0.31).offset(y: -size * 0.135))
        }
        .frame(width: size, height: size)
    }
}
