import SwiftUI

/// 웨이브2-A 시그니처 인터랙션: 점성 액체처럼 동작하는 토글.
///
/// 표준 `Toggle` 의 드롭인 대체(`isOn: Binding<Bool>` 동일 API). 노브가 반대편으로
/// 이동할 때 액체처럼 **늘어났다(trailing stretch) 정착**하고, ON 으로 갈 때 살짝
/// **부풀었다 수축**한다. 트랙은 골드(goldFoil 톤)↔ink 로 채워진다.
///
/// 기법
/// - 노브 + 이동 잔상을 `MetaballView`(`compositingGroup`+`.blur(8)`→`.contrast(18)`)로
///   합성해 두 형태가 점성 액체처럼 융합되게 한다.
/// - 이동은 `interpolatingSpring(stiffness:170, damping:14)` — 언더댐핑이라 정착 시 살짝 출렁인다.
/// - ON 부풀기는 `.snappy(extraBounce:0.3)`.
/// - 햅틱: 토글 시작 `.selection`, 스프링 정착 시 `.lightTap`.
///
/// Reduce Motion 활성 시: blur/stretch 전부 제거하고 트랙·노브 **crossfade + 햅틱**만.
///
/// 비용: 메타볼 합성은 전환(약 0.3s) 동안만 의미가 있고, 설정 화면 전용이라
///   측정 라이브 화면 16ms budget 과 무관하다.
struct LiquidToggle<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder var label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    /// 노브가 이동을 끝내고 정착했을 때를 `interpolatingSpring` 의 fractional progress 로 감지.
    @State private var settleProgress: CGFloat = 0
    /// ON 직후 부풀림 펄스(1.0 = 부푼 상태).
    @State private var swell: CGFloat = 0

    // MARK: - Geometry

    private let trackWidth: CGFloat = 52
    private let trackHeight: CGFloat = 32
    private var knobDiameter: CGFloat { trackHeight - 6 }
    private var travel: CGFloat { trackWidth - knobDiameter - 6 }

    // MARK: - Body

    var body: some View {
        HStack {
            label()
            Spacer(minLength: 12)
            switchBody
                .accessibilityRepresentation {
                    Toggle(isOn: $isOn) { label() }
                }
        }
        .contentShape(Rectangle())
    }

    private var switchBody: some View {
        ZStack(alignment: .leading) {
            track
            knobLayer
        }
        .frame(width: trackWidth, height: trackHeight)
        .opacity(isEnabled ? 1 : 0.45)
        .onTapGesture { toggle() }
        .onChange(of: isOn) { _, _ in animateChange() }
    }

    /// 트랙 골드 채움 애니메이션 — Reduce Motion 시 짧은 crossfade.
    private var fillAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .easeOut(duration: 0.28)
    }

    // MARK: - Track

    private var track: some View {
        ZStack {
            // OFF 베이스 — ink.
            Capsule().fill(AppColors.ink0.opacity(0.22))
            // ON 채움 — goldFoil 톤(로컬 정의: 기반층 AppGradients.goldFoil 부재 대비).
            Capsule()
                .fill(Self.goldFoil)
                .opacity(isOn ? 1 : 0)
                .animation(fillAnimation, value: isOn)
            // 미세한 안쪽 림.
            Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Knob (metaball)

    @ViewBuilder
    private var knobLayer: some View {
        if reduceMotion {
            // Reduce Motion: 메타볼/스트레치 없이 위치만 crossfade.
            knobShape
                .frame(width: knobDiameter, height: knobDiameter)
                .offset(x: isOn ? travel + 3 : 3)
                .animation(.easeInOut(duration: 0.18), value: isOn)
        } else {
            MetaballView(blurRadius: 8, contrast: 18) {
                knobMetaballContent
            }
            // 메타볼은 알파 임계로 흰 실루엣을 만들 뿐이라, 색은 위에서 mask 로 입힌다.
            .foregroundStyle(.white)
            .overlay {
                // 흰 메타볼 실루엣을 마스크로 써서 골드 노브 색 적용.
                Self.knobFill
                    .mask {
                        MetaballView(blurRadius: 8, contrast: 18) { knobMetaballContent }
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
    }

    /// 메타볼 입력: 노브 본체 + 이동 방향 trailing stretch 잔상.
    /// stretch 는 정착할수록(settleProgress→1) 0 으로 줄어 노브만 남는다.
    private var knobMetaballContent: some View {
        let stretch = (1 - settleProgress) * travel * 0.72   // 이동 중 최대 늘어남
        let knobX = (isOn ? travel + 3 : 3)
        let swollen = knobDiameter * (1 + swell * 0.18)      // ON 부풀기
        return ZStack(alignment: .leading) {
            // trailing stretch — 출발점 쪽으로 늘어나는 잔상 캡슐.
            Capsule()
                .frame(width: knobDiameter + stretch, height: knobDiameter * (1 - swell * 0.06))
                .offset(x: knobX - stretch * (isOn ? 1 : 0))
            // 노브 본체.
            Circle()
                .frame(width: swollen, height: swollen)
                .offset(x: knobX - (swollen - knobDiameter) / 2,
                        y: -(swollen - knobDiameter) / 2)
        }
        .frame(width: trackWidth, height: trackHeight, alignment: .leading)
    }

    private var knobShape: some View {
        Circle().fill(Self.knobFill)
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }

    // MARK: - Interaction

    private func toggle() {
        guard isEnabled else { return }
        isOn.toggle()
    }

    /// `isOn` 변경 시 햅틱 + 스프링 진행/정착 + ON 부풀기 구동.
    private func animateChange() {
        HapticManager.trigger(.selection)

        guard !reduceMotion else {
            // crossfade 만 — 진행/부풀기 애니메이션 생략, 정착 햅틱만.
            HapticManager.trigger(.lightTap)
            return
        }

        // 이동: 언더댐핑 스프링. settleProgress 0→1 로 진행하며 stretch 가 0 으로 수축.
        settleProgress = 0
        swell = 0
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 14)) {
            settleProgress = 1
        }
        // ON 으로 갈 때만 부풀었다 수축(snappy bounce).
        if isOn {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0.3)) {
                swell = 1
            }
            withAnimation(.snappy(duration: 0.26, extraBounce: 0.1).delay(0.18)) {
                swell = 0
            }
        }
        // 정착 햅틱 — 스프링이 자리 잡는 시점.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            HapticManager.trigger(.lightTap)
        }
    }

    // MARK: - Local gold tokens (기반층 AppGradients.goldFoil 부재 대비 로컬 정의)

    /// 트랙 채움용 골드 포일 그라데이션.
    private static var goldFoil: LinearGradient {
        LinearGradient(
            colors: [AppColors.accentLight, AppColors.accent, AppColors.accentDark],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// 노브 색 — 미세한 광택을 위한 옅은 세로 그라데이션.
    private static var knobFill: LinearGradient {
        LinearGradient(
            colors: [.white, Color(white: 0.93)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Convenience inits (Toggle parity)

extension LiquidToggle where Label == Text {
    /// `Toggle(_ titleKey:isOn:)` 대응 — 문자열 라벨.
    init(_ title: String, isOn: Binding<Bool>) {
        self._isOn = isOn
        self.label = { Text(title) }
    }
}

// `Toggle(isOn:label:)` 대응(커스텀 라벨)은 `@ViewBuilder` 가 붙은 stored property
// `label` 덕분에 합성 memberwise init `init(isOn:label:)` 으로 그대로 제공된다.

#Preview("LiquidToggle") {
    struct Demo: View {
        @State private var a = true
        @State private var b = false
        @State private var c = true
        var body: some View {
            Form {
                Section("Liquid signature") {
                    LiquidToggle("Silent mode", isOn: $a)
                    LiquidToggle("Keep screen on", isOn: $b)
                    LiquidToggle("Haptics", isOn: $c)
                    LiquidToggle(isOn: $b) {
                        Label("Custom label", systemImage: "drop.fill")
                    }
                }
            }
        }
    }
    return Demo()
}
