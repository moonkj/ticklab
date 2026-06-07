import Combine
import SwiftUI

/// 커스텀 탭바 — 선택 pill 슬라이드(spring) + 탭별 시그니처 아이콘 애니메이션(선택 시 1회 재생).
/// 시스템 TabView 위에 오버레이(콘텐츠/상태는 TabView 가 계속 관리). Reduce Motion 시 모션 생략·pill 슬라이드 유지.
struct AnimatedTabBar: View {
    let tabs: [RootTabView.Tab]
    let selected: RootTabView.Tab
    let onSelect: (RootTabView.Tab) -> Void
    @Namespace private var pillNS

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                glassBar
            } else {
                legacyBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        // 부드러운 스프링 — pill 글라스가 녹아 흐르듯 이동.
        .animation(.spring(response: 0.55, dampingFraction: 0.74), value: selected)
    }

    /// iOS 26 — GlassEffectContainer 안에서 pill 이 glassEffectID 로 morph(액체처럼 녹아 이동).
    @available(iOS 26.0, *)
    private var glassBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    tabLabel(tab)
                        .background {
                            if tab == selected {
                                Capsule(style: .continuous)
                                    .fill(AppColors.interactiveTint.opacity(0.14))
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .glassEffectID("pill", in: pillNS)
                            }
                        }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }

    /// iOS 17–25 — matchedGeometry 슬라이드 pill + material 배경.
    private var legacyBar: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                tabLabel(tab)
                    .background {
                        if tab == selected {
                            Capsule(style: .continuous)
                                .fill(AppColors.interactiveTint.opacity(0.12))
                                .matchedGeometryEffect(id: "pill", in: pillNS)
                        }
                    }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(AppColors.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }

    private func tabLabel(_ tab: RootTabView.Tab) -> some View {
        let isSel = tab == selected
        let color = isSel ? AppColors.interactiveTint : AppColors.ink3
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                AnimatedTabIcon(kind: tab, color: color, play: isSel)
                    .frame(width: 26, height: 26)
                Text(title(tab))
                    .font(.system(size: 11, weight: isSel ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func title(_ tab: RootTabView.Tab) -> String {
        switch tab {
        case .collection: return String(localized: "tab.collection")
        case .today:      return String(localized: "tab.today")
        case .journal:    return String(localized: "tab.journal")
        case .stats:      return String(localized: "tab.stats")
        case .community:  return String(localized: "community.tab.title")
        }
    }
}

// MARK: - 아이콘 디스패치

/// 제목 옆 등 어디서나 쓰는 애니메이션 탭 아이콘 래퍼 — 나타날 때 + 이후 5초마다 시그니처 모션 재생.
struct HeaderTabIcon: View {
    let kind: RootTabView.Tab
    var size: CGFloat = 19
    var color: Color = AppColors.accent
    @State private var play = false
    @Environment(\.accessibilityReduceMotion) private var rm
    // 5초마다 시그니처 모션 재생. 뷰 인스턴스당 1개의 타이머(body 재평가마다 새로 만들지 않도록 stored).
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var body: some View {
        AnimatedTabIcon(kind: kind, color: color, play: play)
            .frame(width: size, height: size)
            .onAppear { trigger() }              // false→true 로 시그니처 모션 트리거
            .onReceive(timer) { _ in trigger() }  // 5초마다 재생
    }
    private func trigger() {
        guard !rm else { return }   // 모션 줄이기 켜짐: 반복 애니메이션 생략
        play = false
        DispatchQueue.main.async { play = true }
    }
}

struct AnimatedTabIcon: View {
    let kind: RootTabView.Tab
    let color: Color
    let play: Bool
    var body: some View {
        switch kind {
        case .collection: TabIconCollection(color: color, play: play)
        case .today:      TabIconToday(color: color, play: play)
        case .journal:    TabIconJournal(color: color, play: play)
        case .stats:      TabIconStats(color: color, play: play)
        case .community:  TabIconCommunity(color: color, play: play)
        }
    }
}

// MARK: - 개별 아이콘 (형상은 TabBarIcons 와 동일, 선택 시 시그니처 모션)

/// 컬렉션 — 2×2 다이얼. 좌→우·위→아래 stagger pop.
private struct TabIconCollection: View {
    let color: Color; let play: Bool
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var sc: [CGFloat] = [1, 1, 1, 1]
    private var lw: CGFloat { size * 0.072 }
    private var d: CGFloat { size * 0.4 }
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let col = CGFloat(i % 2), row = CGFloat(i / 2)
                Circle().stroke(color, lineWidth: lw)
                    .overlay(Circle().fill(color).frame(width: d * 0.2, height: d * 0.2))
                    .frame(width: d, height: d)
                    .scaleEffect(sc[i])
                    .offset(x: col * size * 0.46 - size * 0.23, y: row * size * 0.46 - size * 0.23)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: play) { _, p in if p { run() } }
    }
    private func run() {
        guard !rm else { return }
        sc = [0.2, 0.2, 0.2, 0.2]
        for i in 0..<4 {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.5).delay(Double(i) * 0.06)) { sc[i] = 1 }
        }
    }
}

/// 오늘 — 다이얼 + 침. 선택 시 침이 한 바퀴 sweep.
private struct TabIconToday: View {
    let color: Color; let play: Bool
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var spin: Double = 0
    private var lw: CGFloat { size * 0.075 }
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: lw).frame(width: size * 0.86, height: size * 0.86)
            ZStack {
                Capsule().fill(color).frame(width: lw * 0.9, height: size * 0.30)
                    .offset(y: -size * 0.1).rotationEffect(.degrees(35))
                Capsule().fill(color).frame(width: lw, height: size * 0.20)
                    .offset(y: -size * 0.05).rotationEffect(.degrees(-65))
            }
            .rotationEffect(.degrees(spin))
            Circle().fill(color).frame(width: size * 0.1, height: size * 0.1)
        }
        .frame(width: size, height: size)
        .onChange(of: play) { _, p in
            if p, !rm { withAnimation(.easeInOut(duration: 0.75)) { spin += 360 } }
        }
    }
}

/// 기록 — 책 + 텍스트 라인. 선택 시 라인이 좌→우로 그려짐.
private struct TabIconJournal: View {
    let color: Color; let play: Bool
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var ln: [CGFloat] = [1, 1]
    private var lw: CGFloat { size * 0.072 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .stroke(color, lineWidth: lw)
                .frame(width: size * 0.64, height: size * 0.82)
            Rectangle().fill(color).frame(width: lw, height: size * 0.82).offset(x: -size * 0.16)
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(color).frame(width: size * 0.24, height: lw * 0.8)
                    .scaleEffect(x: ln[i], anchor: .leading)
                    .offset(x: size * 0.06, y: CGFloat(i) * size * 0.16 - size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: play) { _, p in if p { run() } }
    }
    private func run() {
        guard !rm else { return }
        ln = [0, 0]
        for i in 0..<2 {
            withAnimation(.easeOut(duration: 0.3).delay(0.05 + Double(i) * 0.1)) { ln[i] = 1 }
        }
    }
}

/// 분석 — 막대 3. 선택 시 바닥에서 위로 stagger grow.
private struct TabIconStats: View {
    let color: Color; let play: Bool
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var bar: [CGFloat] = [1, 1, 1]
    private var lw: CGFloat { size * 0.075 }
    private let heights: [CGFloat] = [0.42, 0.64, 0.88]
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: size * 0.1) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(color)
                        .frame(width: size * 0.16, height: size * heights[i])
                        .scaleEffect(y: bar[i], anchor: .bottom)
                }
            }
            .frame(height: size * 0.88, alignment: .bottom)
            Rectangle().fill(color).frame(width: size * 0.8, height: lw * 0.8).offset(y: lw)
        }
        .frame(width: size, height: size)
        .onChange(of: play) { _, p in if p { run() } }
    }
    private func run() {
        guard !rm else { return }
        bar = [0, 0, 0]
        for i in 0..<3 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(Double(i) * 0.08)) { bar[i] = 1 }
        }
    }
}

/// 커뮤니티 — 인물 2. 선택 시 순차 bounce.
private struct TabIconCommunity: View {
    let color: Color; let play: Bool
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var off: [CGFloat] = [0, 0]   // [front, back]
    var body: some View {
        ZStack {
            person.scaleEffect(0.85).offset(x: size * 0.2, y: size * 0.05 + off[1])
            person.offset(x: -size * 0.13, y: off[0])
        }
        .offset(y: size * 0.08)
        .frame(width: size, height: size)
        .onChange(of: play) { _, p in if p { run() } }
    }
    private var person: some View {
        VStack(spacing: -size * 0.03) {
            Circle().fill(color).frame(width: size * 0.34, height: size * 0.34)
            Circle().fill(color)
                .frame(width: size * 0.58, height: size * 0.58)
                .mask(Rectangle().frame(width: size * 0.58, height: size * 0.31).offset(y: -size * 0.135))
        }
        .frame(width: size, height: size)
    }
    private func run() {
        guard !rm else { return }
        withAnimation(.easeOut(duration: 0.18)) { off[0] = -3 }
        withAnimation(.easeIn(duration: 0.18).delay(0.18)) { off[0] = 0 }
        withAnimation(.easeOut(duration: 0.18).delay(0.1)) { off[1] = -3 }
        withAnimation(.easeIn(duration: 0.18).delay(0.28)) { off[1] = 0 }
    }
}
