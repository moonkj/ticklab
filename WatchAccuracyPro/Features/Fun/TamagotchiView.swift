import SwiftData
import SwiftUI

/// Screen 22 — Tamagotchi. 시계를 디지털 펫처럼 다루는 전용 화면.
struct TamagotchiView: View {
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @Environment(\.modelContext) private var modelContext
    @State private var activeId: PersistentIdentifier?
    @State private var isWinding: Bool = false
    @State private var reactionVisible: Bool = false
    @State private var windRotation: Double = 0
    @State private var sparkOffsets: [CGFloat] = Array(repeating: 0, count: 8)

    private var active: Watch? {
        if let id = activeId, let w = watches.first(where: { $0.persistentModelID == id }) {
            return w
        }
        return watches.first
    }

    private func energy(for watch: Watch) -> Int {
        WatchMoodService.status(of: watch, in: modelContext).mood.energy
    }

    private func mood(for watch: Watch) -> WatchMoodService.Mood {
        WatchMoodService.status(of: watch, in: modelContext).mood
    }

    private struct MoodTheme {
        let bg: Color
        let face: String
        let label: String
        let emoji: String
    }

    private func theme(for m: WatchMoodService.Mood) -> MoodTheme {
        switch m {
        // Round 123 (Hard Rule 3): label → Localizable.
        case .energetic:  return MoodTheme(bg: Color(red: 0.91, green: 0.96, blue: 0.91),
                                            face: "◕‿◕", label: String(localized: "tamagotchi.mood.energetic"), emoji: "✨")
        case .happy:      return MoodTheme(bg: AppColors.accent50,
                                            face: "◔_◔", label: String(localized: "tamagotchi.mood.happy"), emoji: "🙂")
        case .sleepy:     return MoodTheme(bg: Color(red: 0.95, green: 0.94, blue: 0.90),
                                            face: "─_─", label: String(localized: "tamagotchi.mood.sleepy"), emoji: "😪")
        case .dormant:    return MoodTheme(bg: Color(red: 0.91, green: 0.89, blue: 0.85),
                                            face: "z z z", label: String(localized: "tamagotchi.mood.dormant"), emoji: "💤")
        case .lowBattery: return MoodTheme(bg: Color(red: 0.98, green: 0.92, blue: 0.91),
                                            face: "x_x", label: String(localized: "tamagotchi.mood.low_battery"), emoji: "🪫")
        case .needsWind:  return MoodTheme(bg: Color(red: 0.93, green: 0.92, blue: 0.86),
                                            face: "◐_◐", label: String(localized: "tamagotchi.mood.needs_wind"), emoji: "🌀")
        }
    }

    var body: some View {
        Group {
            if watches.isEmpty {
                emptyState
            } else if let active {
                content(active)
            }
        }
        // Round 139 (Jay Medium): TodayView 진입 카드 라벨 "시계 상태" 와 동기화.
        .navigationTitle(String(localized: "today.states.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("💤").font(.system(size: 60))
            Text(String(localized: "tamagotchi.empty")).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "tamagotchi.empty.hint"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.paper0)
    }

    @ViewBuilder
    private func content(_ watch: Watch) -> some View {
        let m = mood(for: watch)
        let t = theme(for: m)
        ScrollView {
            VStack(spacing: 14) {
                petArea(watch: watch, theme: t, mood: m)
                energyCard(watch: watch)
                actionRow(watch: watch)
                familyCarousel
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 80)
        }
        .background(t.bg.animation(.easeInOut(duration: 0.4)).ignoresSafeArea())
    }

    @ViewBuilder
    private func petArea(watch: Watch, theme: MoodTheme, mood: WatchMoodService.Mood) -> some View {
        VStack(spacing: 12) {
            ZStack {
                // 배경 watch (사진 우선)
                ZStack {
                    if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())
                    } else {
                        WatchSilhouette(watch: watch, size: 200)
                    }
                }
                .rotationEffect(.degrees(isWinding ? windRotation : 0))
                .scaleEffect(mood == .dormant ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: mood == .dormant)
                // 표정 overlay
                Text(theme.face)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.ink0)
                    .opacity(mood == .dormant ? 0.4 : 1)
                    .offset(y: 8)
                // 잠 z
                if mood == .dormant {
                    VStack(spacing: 4) {
                        Text("Z")
                            .font(.system(size: 26, weight: .bold, design: .serif))
                            .foregroundStyle(AppColors.ink3)
                            .offset(x: 70, y: -90)
                            .opacity(0.7)
                        Text("z")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(AppColors.ink3)
                            .offset(x: 60, y: -100)
                            .opacity(0.5)
                    }
                }
                // 충전 reaction
                if reactionVisible {
                    ZStack {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 8, height: 8)
                                .offset(y: -(120 + sparkOffsets[i]))
                                .rotationEffect(.degrees(Double(i) * 45))
                                .opacity(sparkOffsets[i] > 30 ? 0 : 1)
                        }
                        Text("⚡")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(AppColors.accent)
                            .scaleEffect(reactionVisible ? 1.4 : 0.5)
                    }
                }
            }
            .frame(height: 240)

            Text(watch.brand)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppColors.ink0)
            HStack(spacing: 6) {
                Text(theme.emoji)
                Text(theme.label)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .padding(.top, 6)
    }

    private func energyCard(watch: Watch) -> some View {
        let e = energy(for: watch)
        let lastInteraction = WatchMoodService.status(of: watch, in: modelContext)
        return VStack(spacing: 8) {
            HStack {
                Text(String(localized: "tamagotchi.energy").uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                Text("\(e)%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(e) / 100, height: 10)
                        .animation(.easeOut(duration: 0.6), value: e)
                }
            }
            .frame(height: 10)
            HStack {
                Text(lastInteraction.daysSinceInteraction
                     .map { String(format: String(localized: "tamagotchi.last_activity"), $0) }
                     ?? String(localized: "tamagotchi.no_activity"))
                Spacer()
                Text(String(localized: "tamagotchi.sleepy_hint"))
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppColors.ink3)
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @Environment(UserPreferences.self) private var preferences

    private func actionRow(watch: Watch) -> some View {
        let worn = WearLogService.isWornToday(watch, in: modelContext)
        return HStack(spacing: 8) {
            // 태엽 감기 — 감는 중이면 회전 + 라벨 변경.
            petAction(
                icon: isWinding ? "🌀" : "🔧",
                label: isWinding
                    ? String(localized: "tamagotchi.winding")
                    : String(localized: "tamagotchi.wind"),
                state: isWinding ? .active : .primary
            ) {
                wind(watch)
            }
            // 오늘 착용 — wornToday 면 checkmark + accent.
            petAction(
                icon: worn ? "✅" : "🤝",
                label: worn
                    ? String(localized: "tamagotchi.worn_today")
                    : String(localized: "tamagotchi.wear_today"),
                state: worn ? .active : .secondary
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                WearLogService.toggleToday(watch, in: modelContext)
            }
            // 측정 — NavigationLink (state 없음).
            NavigationLink {
                MeasurementView(watch: watch, preferences: preferences)
            } label: {
                petActionBody(
                    icon: "📐",
                    label: String(localized: "tamagotchi.measure"),
                    state: .secondary
                )
            }
        }
    }

    /// 액션 버튼 시각 상태.
    private enum ActionState {
        case primary   // 강조 (dark bg, gold shadow)
        case active    // 현재 진행/완료 상태 (accent bg, ✓)
        case secondary // 일반
    }

    private func petAction(icon: String, label: String, state: ActionState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            petActionBody(icon: icon, label: label, state: state)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func petActionBody(icon: String, label: String, state: ActionState) -> some View {
        let bgColor: Color = {
            switch state {
            case .primary:   return AppColors.primaryDeep
            case .active:    return AppColors.accent50
            case .secondary: return AppColors.paper1
            }
        }()
        let fgColor: Color = {
            switch state {
            case .primary:   return .white
            case .active:    return AppColors.accentDark
            case .secondary: return AppColors.ink0
            }
        }()
        let strokeColor: Color = {
            switch state {
            case .primary:   return .clear
            case .active:    return AppColors.accent
            case .secondary: return AppColors.rule
            }
        }()
        let strokeWidth: CGFloat = (state == .active) ? 1.5 : 1
        let shadowOpacity: Double = (state == .primary) ? 0.2 : 0.04
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 22))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(fgColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(bgColor)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: strokeWidth))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: state == .primary ? AppColors.primaryDeep.opacity(shadowOpacity) : .black.opacity(shadowOpacity),
                radius: state == .primary ? 8 : 2, y: state == .primary ? 4 : 1)
    }

    private var familyCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("tamagotchi.family.title", comment: ""), watches.count).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(watches, id: \.persistentModelID) { w in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            activeId = w.persistentModelID
                        } label: {
                            familyTile(w)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func familyTile(_ watch: Watch) -> some View {
        let isActive = (active?.persistentModelID == watch.persistentModelID)
        let e = energy(for: watch)
        let m = mood(for: watch)
        let t = theme(for: m)
        return VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    AppColors.paper2
                    if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        WatchSilhouette(watch: watch, size: 52)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                Text(t.emoji)
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
                    .background(.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            Text(watch.brand)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
                .lineLimit(1)
            Text("\(e)%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.ink3)
        }
        .frame(width: 80)
        .padding(10)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isActive ? AppColors.accent : .clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Wind action

    private func wind(_ watch: Watch) {
        // Round 165: 재진입 방지 — 이미 wind 중이면 무시.
        guard !isWinding && !reactionVisible else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isWinding = true
        withAnimation(.easeInOut(duration: 0.3)) { windRotation = -15 }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { windRotation = 15 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { windRotation = -15 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { windRotation = 0 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            isWinding = false
            // 충전 reaction.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                reactionVisible = true
            }
            for i in 0..<8 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(i * 50_000_000))
                    withAnimation(.easeOut(duration: 0.9)) {
                        sparkOffsets[i] = 40
                    }
                }
            }
            // 실제 효과: wear log + measurement 활성화 효과.
            WearLogService.toggleToday(watch, in: modelContext)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                reactionVisible = false
            }
            sparkOffsets = Array(repeating: 0, count: 8)
        }
    }
}

#Preview {
    NavigationStack { TamagotchiView() }
        .modelContainer(for: [Watch.self, WearLog.self, WatchMeasurement.self], inMemory: true)
}
