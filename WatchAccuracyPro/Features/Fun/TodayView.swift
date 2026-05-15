import SwiftData
import SwiftUI

/// Round 92 — 새 "오늘" 탭. 사용자 요청으로 설정 탭을 대체.
/// 구성:
/// - 오늘 날짜 + 이번 주 측정 요약
/// - 오늘의 시계 (ShakePick 진입)
/// - 오늘의 다이얼 운세 (DialFortune 진입)
/// - 시계 가족 (컬렉션 갤러리)
struct TodayView: View {
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext

    private let today = Date()

    /// Round 176: RootTabView 가 주입하는 NavigationStack path.
    private let externalPath: Binding<NavigationPath>?
    @State private var localPath = NavigationPath()
    private var pathBinding: Binding<NavigationPath> {
        externalPath ?? $localPath
    }

    init(path: Binding<NavigationPath>? = nil) {
        self.externalPath = path
    }

    /// Round 134 사용자 보고: 오늘 탭에서 대표시계 설정 동작 안 함.
    /// 빈 상태 CTA 가 단순히 첫 시계 detail 로 진입했는데, 사용자는 어느 시계를 고를지 선택권 원함.
    @State private var showingPrimaryPicker = false

    /// Round 176 (사용자 요청 #2): 대표 시계 — 명확히 보이게 강화.
    /// 컬렉션에서 1개만 isPrimary 가 true. nil 이면 "대표 시계 없음" 빈 상태.
    private var primaryWatch: Watch? {
        watches.first(where: { $0.isPrimary })
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    // Round 176 (사용자 UX 요청 #2): 대표 시계 명확화. 설정 됐으면 큰 카드, 아니면 빈 상태 CTA.
                    primaryWatchSection
                    todaysWatchCard
                    fortuneCard
                    // Round 134 사용자 요청: 자기장 카드 항상 노출 (설정 토글 제거).
                    magneticCheckCard
                    watchFamilySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "tab.today"))
            // Round 138 사용자 요청: 기록/통계처럼 inline 고정.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.paper0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            // Round 176: primary card / family card 모두 Watch.self 로 navigate.
            // 기존엔 watchFamilySection 안에만 있어 watches.count==1 일 때 destination 미존재.
            .navigationDestination(for: Watch.self) { w in
                WatchDetailView(watch: w)
            }
        }
    }

    // MARK: - Primary watch (Round 176)

    /// 사용자 UX 요청 #2: 대표 시계가 "어디서 설정하는지 안 보임" — 오늘 탭 최상단에 명시.
    @ViewBuilder
    private var primaryWatchSection: some View {
        if let primary = primaryWatch {
            NavigationLink(value: primary) {
                primaryFilledCard(for: primary)
            }
            .buttonStyle(.plain)
        } else if !watches.isEmpty {
            primaryEmptyCard
        }
    }

    private func primaryFilledCard(for watch: Watch) -> some View {
        let worn = WearLogService.isWornToday(watch, in: modelContext)
        return HStack(spacing: 14) {
            ZStack {
                if let ui = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(AppColors.paper2)
                        .frame(width: 64, height: 64)
                        .overlay(WatchSilhouette(watch: watch, size: 44))
                }
                Circle()
                    .stroke(AppColors.accent, lineWidth: 2)
                    .frame(width: 68, height: 68)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.accent)
                    Text(String(localized: "watch.is_primary").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.accent)
                }
                Text(watch.nickname?.isEmpty == false ? watch.nickname! : watch.model)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                Text(watch.brand)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(1)
            }
            Spacer()
            // 오늘 착용 표시 (탭으로 토글하진 않음 — 상세에서 토글).
            if worn {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                    Text(String(localized: "watch.worn_today"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.accent50)
                .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accentLight, lineWidth: 1.5))
    }

    /// 시계는 있는데 대표 미설정 — 빈 상태 안내 + 첫 시계 상세로 진입 CTA.
    private var primaryEmptyCard: some View {
        let fallback = watches.first
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(AppColors.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(AppColors.paper2))
                Image(systemName: "star")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.ink3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "today.primary.empty.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(String(localized: "today.primary.empty.body"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            if fallback != nil {
                // Round 134 BUG FIX: 단순 첫 시계 detail 진입 → 시계 picker sheet 으로 명확히 선택.
                Button {
                    showingPrimaryPicker = true
                } label: {
                    Text(String(localized: "today.primary.empty.cta"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.paper0)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .sheet(isPresented: $showingPrimaryPicker) {
            PrimaryWatchPickerSheet(watches: watches) { selected in
                setPrimary(selected)
                showingPrimaryPicker = false
            }
        }
    }

    /// Round 134: 컬렉션 내 다른 시계의 isPrimary 를 false 로 reset 후 선택 시계만 true.
    private func setPrimary(_ watch: Watch) {
        for w in watches where w.id != watch.id && w.isPrimary {
            w.isPrimary = false
        }
        watch.isPrimary = true
        try? modelContext.save()
    }

    // MARK: - Header

    private var headerSection: some View {
        // Round 102 (UX H1): ko_KR 하드코딩 제거 → 시스템 로케일 따름.
        let dateStr = today.formatted(.dateTime.month().day().weekday(.abbreviated))

        // 이번 주 측정 횟수.
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekMeasurements = watches.flatMap { $0.measurements }.filter { $0.timestamp >= weekStart }
        return VStack(alignment: .leading, spacing: 8) {
            Text(dateStr)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "today.greeting"))
                .font(.system(size: 26, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.ink0)
            HStack(spacing: 14) {
                statPill(value: "\(watches.count)", label: String(localized: "today.stat.watches"))
                statPill(value: "\(weekMeasurements.count)", label: String(localized: "today.stat.this_week"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LinearGradient(
            colors: [AppColors.accent50, AppColors.paper1],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.ink2)
        }
    }

    // MARK: - Today's Watch

    private var todaysWatchCard: some View {
        NavigationLink {
            ShakePickView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [AppColors.accentLight, AppColors.accent],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 5, endRadius: 50))
                        .frame(width: 64, height: 64)
                    Image(systemName: "dice.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "today.shake.title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "today.shake.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fortune

    private var fortuneCard: some View {
        NavigationLink {
            DialFortuneView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.10, green: 0.13, blue: 0.22),
                                     Color(red: 0.17, green: 0.20, blue: 0.32)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.55))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "today.fortune.title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "today.fortune.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Magnetic Field Check (Round 180, Sora)

    private var magneticCheckCard: some View {
        NavigationLink {
            MagneticFieldView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.18, green: 0.32, blue: 0.55),
                                     Color(red: 0.30, green: 0.46, blue: 0.72)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "today.card.magnetic.title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "today.card.magnetic.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.paper1)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Watch Family

    @ViewBuilder
    private var watchFamilySection: some View {
        // Round 138 (사용자 요청): "시계 가족" → "시계 상태" 로 변경.
        // 등록된 모든 시계의 현재 mood (energy / happy / sleepy / dormant) 를 한눈에.
        if !watches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "today.states.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.ink2)
                    Spacer()
                    Text("\(watches.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    // Round 141 (Sora #3): LazyHStack 으로 — 100개 시계 등록 시에도 viewport 카드만 인스턴스화.
                    LazyHStack(spacing: 12) {
                        // Round 138 사용자 요청 (재반영): state 카드 클릭 → TamagotchiView 진입 (태엽 감기/착용/배터리 인터랙션).
                        ForEach(watches) { w in
                            NavigationLink {
                                TamagotchiView()
                            } label: {
                                stateCard(for: w)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Round 138: 시계 상태 카드 — mood + 에너지 게이지 + brand/model.
    private func stateCard(for watch: Watch) -> some View {
        let status = WatchMoodService.status(of: watch, in: modelContext)
        let energy = status.mood.energy
        return VStack(spacing: 8) {
            ZStack {
                if let ui = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                } else {
                    Circle().fill(AppColors.paper2).frame(width: 72, height: 72)
                        .overlay(WatchSilhouette(watch: watch, size: 48))
                }
                if watch.isPrimary {
                    Circle().stroke(AppColors.accent, lineWidth: 2).frame(width: 76, height: 76)
                }
                // mood emoji bottom-right.
                Text(status.mood.emoji)
                    .font(.system(size: 22))
                    .offset(x: 26, y: 26)
            }
            VStack(spacing: 1) {
                Text(watch.brand)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                Text(watch.model)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(1)
            }
            // energy gauge.
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.paper2).frame(width: 84, height: 4)
                Capsule().fill(energyColor(energy)).frame(width: 84 * CGFloat(energy) / 100, height: 4)
            }
            Text("\(energy)%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.ink2)
        }
        .frame(width: 96)
        .padding(.vertical, 10)
    }

    private func energyColor(_ e: Int) -> Color {
        if e >= 70 { return AppColors.success }
        if e >= 40 { return AppColors.warning }
        return AppColors.danger
    }

    private func familyCard(for watch: Watch) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let ui = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(AppColors.paper2)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "applewatch")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColors.ink3)
                        )
                }
                if watch.isPrimary {
                    Circle()
                        .stroke(AppColors.accent, lineWidth: 2)
                        .frame(width: 76, height: 76)
                }
            }
            // Round 138 사용자 요청: 시계 가족 캐러셀에도 brand + model 두 줄.
            VStack(spacing: 1) {
                Text(watch.brand)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                Text(watch.nickname?.isEmpty == false ? watch.nickname! : watch.model)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(1)
            }
            .frame(width: 84)
        }
    }
}

/// Round 134: 대표시계 선택 sheet — 컬렉션의 시계 중 하나 골라 setPrimary 호출.
private struct PrimaryWatchPickerSheet: View {
    let watches: [Watch]
    let onSelect: (Watch) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(watches) { watch in
                    Button {
                        onSelect(watch)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if let ui = PhotoCache.image(for: watch.id, data: watch.photoData) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } else {
                                    Circle().fill(AppColors.paper2).frame(width: 44, height: 44)
                                        .overlay(WatchSilhouette(watch: watch, size: 30))
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(watch.brand)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.ink0)
                                Text(watch.model)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.ink2)
                            }
                            Spacer()
                            if watch.isPrimary {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "today.primary.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TodayView()
        .environment(UserPreferences())
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
