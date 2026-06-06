import SwiftUI

/// 오토매틱 무브먼트 **로터** — 당김 진행도(progress)로 회전하거나, 새로고침 중(spinning) 연속 회전.
/// 반원 스켈레톤 추(秤) + 베어링 + 중심 보석. 배경 투명. Reduce Motion 정적.
struct AutomaticRotorView: View {
    var spinning: Bool = false      // 새로고침 중 — 연속 회전(관성)
    var progress: Double = 0        // 당기는 중 — 0..1.4 회전량
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !spinning || reduceMotion)) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let angle: Double = spinning
                    ? (reduceMotion ? 0 : t * 5.5)              // 연속 회전(≈0.9 turn/s)
                    : progress * .pi * 2.0                       // 당김 비례(임계까지 ≈1바퀴)
                draw(gc, size: size, angle: angle)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ gc: GraphicsContext, size: CGSize, angle: Double) {
        let cx = size.width / 2, cy = size.height / 2
        let R = min(size.width, size.height) / 2 * 0.82
        let gold = AppColors.accent, goldL = AppColors.accentLight, goldD = AppColors.accentDark
        let plate = Color(red: 0.10, green: 0.11, blue: 0.18)
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        // 베어링 링
        gc.stroke(circle(cx, cy, R + 2), with: .color(gold.opacity(0.3)), lineWidth: 1.5)
        var r = gc
        r.translateBy(x: cx, y: cy); r.rotate(by: .radians(angle))
        // 반원 추 — 바깥 호 + 안쪽 호로 닫아 반달 링.
        var p = Path()
        p.addArc(center: .zero, radius: R, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addArc(center: .zero, radius: R * 0.42, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        r.fill(p, with: .linearGradient(Gradient(colors: [goldD, goldL, goldD]),
                                        startPoint: CGPoint(x: -R, y: 0), endPoint: CGPoint(x: R, y: 0)))
        r.stroke(p, with: .color(gold), lineWidth: 1.4)
        // 스켈레톤 컷아웃
        for k in 0..<3 {
            let a = Double.pi * 0.3 + Double(k) * Double.pi * 0.2
            r.fill(circle(CGFloat(cos(a)) * R * 0.68, CGFloat(sin(a)) * R * 0.68, R * 0.11), with: .color(plate))
        }
        // 중심 보석
        r.fill(circle(0, 0, R * 0.15), with: .color(gold))
        r.fill(circle(0, 0, R * 0.06), with: .color(plate))
    }
}

private struct RotorOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 자동 로터 pull-to-refresh ScrollView — 당기면 로터가 당긴 양만큼 돌고, 임계 넘겨 놓으면 새로고침 +
/// 로터 연속 회전. 시스템 스피너 대신 무브먼트 메타포(손목 움직임=회전).
/// 측정 라이브 화면엔 미사용(Hard Rule #4). Reduce Motion 시 로터 정적.
struct RotorRefreshScrollView<Content: View>: View {
    let onRefresh: () async -> Void
    @ViewBuilder var content: Content

    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var isRefreshing = false
    private let threshold: CGFloat = 72

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            scroll18
        } else {
            // iOS 17 폴백 — 시스템 refreshable(로터 당김 비례는 없지만 동작 보장).
            ScrollView { content }.refreshable { await onRefresh() }
        }
    }

    @available(iOS 18.0, *)
    private var scroll18: some View {
        ScrollView {
            VStack(spacing: 0) {
                let headerH = isRefreshing ? threshold : min(max(0, pull), threshold)
                AutomaticRotorView(spinning: isRefreshing,
                                   progress: Double(min(3.0, max(0, pull) / threshold)))
                    .frame(width: 38, height: 38)
                    .opacity(headerH > 6 ? 1 : 0)
                    .frame(height: headerH)
                    .clipped()
                content
            }
        }
        // 신뢰성 있는 스크롤 오프셋 — 최상단 rest=0, 위로 당기면(overscroll) 음수.
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, v in
            guard !isRefreshing else { return }
            let p = max(0, -v)                 // 당김량
            pull = p
            if p >= threshold {
                armed = true
            } else if armed, p < threshold {   // 임계 넘긴 뒤 놓음 → 새로고침
                armed = false
                isRefreshing = true
                HapticManager.trigger(.selection)
                Task {
                    await onRefresh()
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isRefreshing = false; pull = 0
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RotorRefreshScrollView(onRefresh: { try? await Task.sleep(nanoseconds: 1_500_000_000) }) {
        LazyVStack {
            ForEach(0..<20, id: \.self) { i in
                Text("Row \(i)").frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        }
    }
    .background(AppColors.paper0)
}
