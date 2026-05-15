import CoreMotion
import SwiftData
import SwiftUI

/// Screen 21 — ShakePick. 폰을 흔들거나 버튼으로 오늘의 시계 추천.
struct ShakePickView: View {
    @Query private var watches: [Watch]
    @Environment(UserPreferences.self) private var preferences
    @State private var phase: Phase = .idle
    @State private var picked: Watch?
    /// Round 138: "차고나가기" 결과 toast.
    @State private var wornToastVisible: Bool = false
    @State private var wornLogged: Bool = false
    @State private var reason: String = ""
    @State private var shakeIntensity: Double = 0
    @State private var motionManager = CMMotionManager()
    @State private var dotOffsets: [CGSize] = Array(repeating: .zero, count: 8)

    enum Phase { case idle, shaking, reveal }

    /// Round 161/175: 워치 컨셉 무관 generic 문구. 8개 localized.
    private var reasons: [String] {
        (1...8).map { NSLocalizedString("shake.reason.\($0)", comment: "") }
    }

    /// Round 93 (정수민 #4): 시계 타입별 맞춤 멘트 풀.
    /// 추출 우선순위: nickname 있으면 nickname 멘트 → brand category → movement type → generic.
    private func tailoredReason(for watch: Watch) -> String {
        let brand = watch.brand.lowercased()
        // Dress / formal — Cartier Tank, JLC Reverso, Patek Calatrava, Hermès, Chanel
        let dressBrands = ["cartier", "jaeger", "patek", "hermès", "hermes", "chanel", "piaget", "vacheron", "lange", "breguet", "blancpain"]
        let sportBrands = ["g-shock", "casio", "seiko", "tudor", "rolex", "panerai", "hublot", "richard mille", "audemars", "tag heuer", "breitling", "iwc", "omega seamaster", "doxa", "sinn", "bremont", "fortis"]
        let modelLower = watch.model.lowercased()
        let isDress = dressBrands.contains(where: brand.contains) ||
                      modelLower.contains("dress") || modelLower.contains("tank") ||
                      modelLower.contains("reverso") || modelLower.contains("calatrava")
        let isSport = sportBrands.contains(where: brand.contains) ||
                      modelLower.contains("diver") || modelLower.contains("chrono") ||
                      modelLower.contains("g-shock") || modelLower.contains("gmt") ||
                      modelLower.contains("speedmaster") || modelLower.contains("submariner")
        var pool: [String] = []
        if isDress {
            pool = (1...4).map { NSLocalizedString("shake.reason.dress.\($0)", comment: "") }
        } else if isSport {
            pool = (1...4).map { NSLocalizedString("shake.reason.sport.\($0)", comment: "") }
        }
        if watch.movementType == .manual {
            pool += (1...2).map { NSLocalizedString("shake.reason.manual.\($0)", comment: "") }
        }
        if pool.isEmpty {
            pool = reasons
        }
        return pool.randomElement() ?? reasons[0]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroArea
                cta
                tip
                scheduleCard
                if !watches.isEmpty {
                    historySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .background(LinearGradient(colors: [AppColors.paper0, AppColors.accent50],
                                   startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea())
        .navigationTitle(String(localized: "shake.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startShakeDetection() }
        .onDisappear { stopShakeDetection() }
        // Round 138: "차고 나가기" 동작 확인용 toast.
        .overlay(alignment: .top) {
            if wornToastVisible {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppColors.success)
                    Text(String(localized: "wear.toast.logged"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.paper1)
                .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: wornToastVisible)
    }

    private var heroArea: some View {
        ZStack {
            if phase != .reveal {
                discView
            } else if let picked {
                revealView(picked)
            }
        }
        .frame(height: 340)
    }

    private var discView: some View {
        ZStack {
            // Radial dots when shaking
            if phase == .shaking {
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 8, height: 8)
                        .opacity(0.5 + shakeIntensity * 0.5)
                        .offset(y: -(110 + shakeIntensity * 30))
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            // The disc
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.98, green: 0.965, blue: 0.91),
                             AppColors.accentLight,
                             AppColors.accent],
                    center: UnitPoint(x: 0.35, y: 0.25),
                    startRadius: 5, endRadius: 100))
                .frame(width: 200, height: 200)
                .shadow(color: AppColors.accent.opacity(0.45), radius: 30, y: 30)
                .overlay(
                    Text("?")
                        .font(.system(size: 84, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: AppColors.accentDark.opacity(0.6), radius: 6, y: 4)
                )
                // Round 165: 진폭 24→14 로 축소 (SE 화면에서 disc 가장자리 넘어가던 문제).
                .offset(x: CGFloat.random(in: -1...1) * shakeIntensity * 14,
                        y: CGFloat.random(in: -1...1) * shakeIntensity * 14)
                .rotationEffect(.degrees(CGFloat.random(in: -1...1) * shakeIntensity * 12))
                .animation(.easeInOut(duration: 0.07), value: shakeIntensity)
        }
    }

    private func revealView(_ watch: Watch) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.98, green: 0.965, blue: 0.91),
                                 AppColors.accentLight, AppColors.accent],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 5, endRadius: 100))
                    .frame(width: 200, height: 200)
                    .shadow(color: AppColors.accent.opacity(0.5), radius: 30, y: 30)
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                } else {
                    WatchSilhouette(watch: watch, size: 140)
                }
            }
            .transition(.scale.combined(with: .opacity))
            Text(String(localized: "shake.title.eyebrow").uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(AppColors.accentDark)
            Text(watch.brand)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppColors.ink0)
            Text(watch.model)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.ink2)
            Text("💫 \(reason)")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.accentDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.accent50)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var cta: some View {
        if phase != .reveal {
            Button(action: shake) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 18))
                    Text(String(localized: phase == .shaking ? "shake.cta.shaking" : "shake.cta.idle"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(AppColors.primaryDeep)
                .clipShape(Capsule())
                .shadow(color: AppColors.primaryDeep.opacity(0.3), radius: 8, y: 4)
            }
            // Round 116 (A11y): VoiceOver 가 레이블 + 힌트 읽도록.
            .accessibilityLabel(String(localized: "shake.cta.a11y.label"))
            .accessibilityHint(String(localized: "shake.cta.a11y.hint"))
            .buttonStyle(.plain)
            .disabled(phase == .shaking || watches.isEmpty)
        } else {
            HStack(spacing: 8) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    phase = .idle
                    picked = nil
                    wornLogged = false
                } label: {
                    Text(String(localized: "shake.cta.retry"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.ink1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.paper1)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    guard !wornLogged,
                          let picked,
                          let watch = watches.first(where: { $0.id == picked.id }) else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    WearLogService.toggleToday(watch, in: modelContext)
                    WatchMoodService.invalidate(for: watch)
                    withAnimation(.easeOut(duration: 0.15)) { wornLogged = true }
                    wornToastVisible = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        wornToastVisible = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if wornLogged {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                        }
                        Text(wornLogged
                             ? String(localized: "shake.cta.wear.done")
                             : String(localized: "shake.cta.wear"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(wornLogged ? AnyButtonStyle(WornDoneButtonStyle()) : AnyButtonStyle(WearButtonStyle()))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    @Environment(\.modelContext) private var modelContext

    private var tip: some View {
        Text(String(localized: "shake.tip"))
            .font(.system(size: 11))
            .foregroundStyle(AppColors.ink3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    private var scheduleCard: some View {
        @Bindable var preferences = preferences
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: NSLocalizedString("shake.schedule.daily", comment: ""),
                            preferences.randomPickHour, preferences.randomPickMinute))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                // Round 138 사용자 요청: "2개 이상 등록되어 활성화" subtitle 제거 — 시계 1개로도 동작.
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { preferences.randomPickEnabled },
                set: { newValue in
                    preferences.randomPickEnabled = newValue
                    NotificationService.scheduleRandomPick(
                        watches: watches,
                        hour: preferences.randomPickHour,
                        minute: preferences.randomPickMinute,
                        enabled: newValue
                    )
                }
            ))
            .labelsHidden()
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "shake.section.mywatches").uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                // Round 143 (Sora #5): LazyHStack — 시계 많을 때 viewport 만 인스턴스화.
                LazyHStack(spacing: 8) {
                    ForEach(watches) { w in
                        VStack(spacing: 6) {
                            ZStack {
                                AppColors.paper2
                                if let img = PhotoCache.image(for: w.id, data: w.photoData) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else {
                                    WatchSilhouette(watch: w, size: 52)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(w.brand)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                                .lineLimit(1)
                        }
                        .frame(width: 84)
                        .padding(8)
                        .background(AppColors.paper1)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - Shake action

    private func shake() {
        guard !watches.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        phase = .shaking
        shakeIntensity = 0
        // Round 104 (BUG-6): 비동기 Task 내 watches 스냅샷 고정 — 비동기 중 삭제된 시계 접근 방지.
        let watchesSnapshot = watches
        Task {
            for _ in 0..<22 {
                try? await Task.sleep(nanoseconds: 70_000_000)
                shakeIntensity = min(1.0, shakeIntensity + 0.06)
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                let pick = watchesSnapshot.randomElement()
                picked = pick
                // Round 93: 시계 컨셉에 맞는 멘트.
                reason = pick.map { tailoredReason(for: $0) } ?? (reasons.randomElement() ?? reasons[0])
                phase = .reveal
                shakeIntensity = 0
            }
        }
    }

    // MARK: - CoreMotion shake detection

    private func startShakeDetection() {
        // Round 116 (A11y): tremor/VoiceOver 사용자에게 accelerometer 오발동 방지.
        guard motionManager.isAccelerometerAvailable,
              !UIAccessibility.isVoiceOverRunning else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0
        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let a = data?.acceleration else { return }
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            // Round 165: watches 0개일 때 shake 자동 감지로 빈 reveal 진입하던 버그 가드.
            if magnitude > 2.2, phase == .idle, !watches.isEmpty {
                shake()
            }
        }
    }

    private func stopShakeDetection() {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }
}

/// AnyButtonStyle 타입 소거 래퍼 — 조건부 ButtonStyle 전환용.
private struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (ButtonStyle.Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

/// 차고나가기 기본 스타일 — neutral, 누르는 순간 골드.
private struct WearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? AppColors.accent : AppColors.ink1)
            .background(configuration.isPressed ? AppColors.accent50 : AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(configuration.isPressed ? AppColors.accentLight : AppColors.rule, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 착용 완료 후 스타일 — 골드 고정 + 비활성.
private struct WornDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColors.accent)
            .background(AppColors.accent50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentLight, lineWidth: 1))
    }
}

#Preview {
    NavigationStack { ShakePickView() }
        .modelContainer(for: [Watch.self, WearLog.self], inMemory: true)
        .environment(UserPreferences())
}
