import SwiftData
import SwiftUI

// MARK: - BadgesView

struct BadgesView: View {
    @Query private var watches: [Watch]
    @Query private var measurements: [WatchMeasurement]
    @Query private var journals: [JournalEntry]
    @Query private var wearLogs: [WearLog]

    @State private var filter: BadgeFilter = .all
    @State private var selectedBadge: Badge? = nil
    @State private var toastBadge: Badge? = nil
    @AppStorage("badges.seenIds") private var seenIdsJSON: String = "[]"

    // MARK: Types

    enum BadgeFilter: String, CaseIterable {
        case all, earned, locked
        var label: String {
            switch self {
            case .all:    return String(localized: "badges.filter.all")
            case .earned: return String(localized: "badges.filter.earned")
            case .locked: return String(localized: "badges.filter.locked")
            }
        }
    }

    enum Rarity {
        case common, rare, epic, legendary
        var label: String {
            switch self {
            case .common:    return "COMMON"
            case .rare:      return "RARE"
            case .epic:      return "EPIC"
            case .legendary: return "LEGENDARY"
            }
        }
        var color: Color {
            switch self {
            case .common:    return Color(red: 0.435, green: 0.416, blue: 0.357)
            case .rare:      return AppColors.info
            case .epic:      return Color(red: 0.478, green: 0.310, blue: 0.722)
            case .legendary: return AppColors.accent
            }
        }
        var gradientColors: [Color] {
            switch self {
            case .common:    return [color.opacity(0.9), color.opacity(0.65)]
            case .rare:      return [color, color.opacity(0.7)]
            case .epic:      return [color, Color(red: 0.28, green: 0.14, blue: 0.52)]
            case .legendary: return [AppColors.accent, AppColors.accentDark]
            }
        }
    }

    struct Badge: Identifiable, Equatable {
        let id: String
        let name: String
        let desc: String
        let condition: String
        let emoji: String
        let rarity: Rarity
        let earned: Bool
        let progress: Int
        let total: Int
        static func == (a: Badge, b: Badge) -> Bool { a.id == b.id && a.earned == b.earned }
    }

    // MARK: - Computed badges

    private var badges: [Badge] {
        let registered       = watches.count
        let totalM           = measurements.count
        // Bug Fix: hour<5 는 자정(b24)과 범위 겹침 → 새벽 4시~7시로 분리.
        let earlyMorning     = measurements.filter { let h = Calendar.current.component(.hour, from: $0.timestamp); return h >= 4 && h < 7 }.count
        let lateNight        = measurements.filter { Calendar.current.component(.hour, from: $0.timestamp) >= 22 }.count
        let distinctBrands   = Set(watches.map(\.brand)).count
        let journalCount     = journals.count
        // Bug Fix: count distinct calendar days per watch (not raw row count).
        let longestWear: Int = {
            let grouped = Dictionary(grouping: wearLogs, by: { $0.watch?.id })
            return grouped.values.map { logs in
                Set(logs.map { Calendar.current.startOfDay(for: $0.date) }).count
            }.max() ?? 0
        }()
        let maxRuns: Int = {
            let grouped = Dictionary(grouping: measurements, by: { $0.watch?.id })
            return grouped.values.map { $0.count }.max() ?? 0
        }()
        let hasGMT        = watches.contains { $0.model.lowercased().contains("gmt") }
        let hasMoon       = watches.contains { $0.model.lowercased().contains("moon") || ($0.caliber?.lowercased().contains("moon") ?? false) }
        let hasDiver      = watches.contains { $0.model.lowercased().contains("sub") || $0.model.lowercased().contains("diver") }
        let hasChrono     = watches.contains { $0.model.lowercased().contains("chronograph") || $0.model.lowercased().contains("chrono") }
        // Bug Fix: b20/b32 vintage 정의 통일 → purchaseDate < 2000 기준.
        // 이전엔 b20 이 MovementDB BPH 기준 (18000/19800) 이어서 b32 와 불일치.
        let hasVintage: Bool = watches.contains { w in
            guard let pd = w.purchaseDate else { return false }
            return Calendar.current.component(.year, from: pd) < 2000
        }
        let hasCOSCM      = measurements.contains { $0.rateSecondsPerDay >= -4 && $0.rateSecondsPerDay <= 6 }
        let hasGradeA     = measurements.contains { $0.confidenceScore >= 75 && abs($0.rateSecondsPerDay) <= 30 }
        let hasPerfectB   = measurements.contains { $0.beatErrorMs < 0.1 }

        // ── 신규 배지 조건 ──────────────────────────────────────────────────
        // b23: 칼리버 최초 입력
        let hasCaliber = watches.contains { $0.caliber != nil && !($0.caliber!.isEmpty) }
        // b24: 자정 측정 5회
        let midnightM = measurements.filter {
            let h = Calendar.current.component(.hour, from: $0.timestamp); return h < 2
        }.count
        // b25: 저널 7일 연속 — 날짜 set 에서 연속 7일 탐색
        let consecutiveJournalDays: Int = {
            let days = Set(journals.map {
                Calendar.current.startOfDay(for: $0.timestamp)
            }).sorted()
            var maxStreak = 0; var streak = 1
            for i in 1..<days.count {
                if Calendar.current.dateComponents([.day], from: days[i-1], to: days[i]).day == 1 {
                    streak += 1; maxStreak = max(maxStreak, streak)
                } else { streak = 1 }
            }
            return days.isEmpty ? 0 : max(maxStreak, streak)
        }()
        // b26: 5분(300s) 이상 측정 25회
        let longMeasurements = measurements.filter { $0.durationSeconds >= 300 }.count
        // b27: 같은 시계를 같은 날 2회 이상 측정한 날 10일.
        // Bug Fix: 이전 코드는 watchId 를 key 에서 제거해 서로 다른 시계의 날짜가 collapse 됨.
        // 수정: (watchId, day) 복합키를 그대로 사용 → count 만 필터링.
        let sameDayDoubleDays: Int = {
            let grouped = Dictionary(grouping: measurements) { m -> String in
                let day = Calendar.current.startOfDay(for: m.timestamp)
                return "\(m.watch?.id.uuidString ?? "nil")_\(day.timeIntervalSince1970)"
            }
            return grouped.filter { $0.value.count >= 2 }.count
        }()
        // b28: 저널 20개 이상 + mood 4가지 이상
        let moodVariety = Set(journals.map { $0.moodRaw }).count
        let hasEmotionSpectrum = journals.count >= 20 && moodVariety >= 4
        // b29: 진폭 300도 이상 + 신뢰도 70 이상 측정 5회
        let highAmplitudeM = measurements.filter {
            ($0.amplitudeDegrees ?? 0) >= 300 && $0.confidenceScore >= 70
        }.count
        // b30: 다른 BPH 종류 3가지 이상 각각 1회 측정
        let bphBuckets: Set<Int> = [18000, 21600, 28800, 36000]
        let measuredBPHTypes = Set(measurements.map { $0.bph }.filter { bphBuckets.contains($0) }).count
        // b31: 4계절 각 1회 이상 측정
        let seasons = Set(measurements.map { m -> Int in
            let month = Calendar.current.component(.month, from: m.timestamp)
            switch month {
            case 3...5: return 0; case 6...8: return 1; case 9...11: return 2; default: return 3
            }
        })
        let hasAllSeasons = seasons.count == 4
        // b32: 구매연도 2000년 이전 시계 5개 + 각 1회 측정
        let vintageWatches = watches.filter {
            guard let pd = $0.purchaseDate else { return false }
            return Calendar.current.component(.year, from: pd) < 2000
        }
        let measuredVintageIds = Set(measurements.compactMap { m -> UUID? in
            guard vintageWatches.contains(where: { $0.id == m.watch?.id }) else { return nil }
            return m.watch?.id
        })
        let hasVintageHistory = measuredVintageIds.count >= 5

        let newParams = NewBadgeParams(
            hasCaliber: hasCaliber, midnightM: midnightM,
            consecutiveJournalDays: consecutiveJournalDays, longMeasurements: longMeasurements,
            sameDayDoubleDays: sameDayDoubleDays, hasEmotionSpectrum: hasEmotionSpectrum,
            highAmplitudeM: highAmplitudeM, measuredBPHTypes: measuredBPHTypes,
            seasonsCount: seasons.count, hasAllSeasons: hasAllSeasons,
            vintageCount: measuredVintageIds.count, hasVintageHistory: hasVintageHistory
        )
        let partial = makeBadges(
            registered: registered, totalM: totalM,
            earlyMorning: earlyMorning, lateNight: lateNight,
            distinctBrands: distinctBrands, journalCount: journalCount,
            longestWear: longestWear, maxRuns: maxRuns,
            hasGMT: hasGMT, hasMoon: hasMoon, hasDiver: hasDiver,
            hasChrono: hasChrono, hasVintage: hasVintage,
            hasCOSCM: hasCOSCM, hasGradeA: hasGradeA, hasPerfectB: hasPerfectB,
            allOtherEarned: false, new: newParams
        )
        let allOther = partial.filter { $0.id != "b12" }.allSatisfy(\.earned)
        return makeBadges(
            registered: registered, totalM: totalM,
            earlyMorning: earlyMorning, lateNight: lateNight,
            distinctBrands: distinctBrands, journalCount: journalCount,
            longestWear: longestWear, maxRuns: maxRuns,
            hasGMT: hasGMT, hasMoon: hasMoon, hasDiver: hasDiver,
            hasChrono: hasChrono, hasVintage: hasVintage,
            hasCOSCM: hasCOSCM, hasGradeA: hasGradeA, hasPerfectB: hasPerfectB,
            allOtherEarned: allOther, new: newParams
        )
    }

    private struct NewBadgeParams {
        let hasCaliber: Bool; let midnightM: Int
        let consecutiveJournalDays: Int; let longMeasurements: Int
        let sameDayDoubleDays: Int; let hasEmotionSpectrum: Bool
        let highAmplitudeM: Int; let measuredBPHTypes: Int
        let seasonsCount: Int; let hasAllSeasons: Bool
        let vintageCount: Int; let hasVintageHistory: Bool
    }

    private func makeBadges(
        registered: Int, totalM: Int,
        earlyMorning: Int, lateNight: Int,
        distinctBrands: Int, journalCount: Int,
        longestWear: Int, maxRuns: Int,
        hasGMT: Bool, hasMoon: Bool, hasDiver: Bool,
        hasChrono: Bool, hasVintage: Bool,
        hasCOSCM: Bool, hasGradeA: Bool, hasPerfectB: Bool,
        allOtherEarned: Bool, new: NewBadgeParams
    ) -> [Badge] {
        func nm(_ id: String) -> String { NSLocalizedString("badges.\(id).name", comment: "") }
        func ds(_ id: String) -> String { NSLocalizedString("badges.\(id).desc", comment: "") }
        func cd(_ id: String) -> String { NSLocalizedString("badges.\(id).condition", comment: "") }
        func b(_ id: String, _ emoji: String, _ r: Rarity, _ earned: Bool, _ prog: Int, _ tot: Int) -> Badge {
            Badge(id: id, name: nm(id), desc: ds(id), condition: cd(id),
                  emoji: emoji, rarity: r, earned: earned, progress: prog, total: tot)
        }
        return [
            b("b10", "✅", .common,    totalM >= 1,             min(totalM, 1),   1),
            b("b7",  "✈️", .common,    hasGMT,                  hasGMT ? 1:0,     1),
            b("b4",  "🌅", .common,    earlyMorning >= 10,      min(earlyMorning,10), 10),
            b("b16", "🌙", .common,    lateNight >= 5,          min(lateNight,5), 5),
            b("b17", "🔟", .common,    totalM >= 10,            min(totalM,10),   10),
            b("b1",  "🌊", .rare,      hasDiver,                hasDiver ? 1:0,   1),
            b("b6",  "🌕", .rare,      hasMoon,                 hasMoon ? 1:0,    1),
            b("b9",  "🎨", .rare,      distinctBrands >= 5,     min(distinctBrands,5), 5),
            b("b3",  "🎯", .rare,      longestWear >= 30,       min(longestWear,30), 30),
            b("b11", "📓", .rare,      journalCount >= 50,      min(journalCount,50), 50),
            b("b13", "🏅", .rare,      hasCOSCM,                hasCOSCM ? 1:0,   1),
            b("b18", "⏱️", .rare,      totalM >= 50,            min(totalM,50),   50),
            b("b20", "🕰️", .rare,      hasVintage,              hasVintage ? 1:0, 1),
            b("b2",  "🏆", .epic,      registered >= 5,         min(registered,5), 5),
            b("b8",  "💯", .epic,      maxRuns >= 100,          min(maxRuns,100), 100),
            b("b14", "🌟", .epic,      hasGradeA,               hasGradeA ? 1:0,  1),
            b("b15", "🎵", .epic,      hasPerfectB,             hasPerfectB ? 1:0, 1),
            b("b21", "🔩", .epic,      hasChrono,               hasChrono ? 1:0,  1),
            b("b22", "🎖️", .epic,      registered >= 10,        min(registered,10), 10),
            b("b5",  "⚙️", .legendary, distinctBrands >= 7,     min(distinctBrands,7), 7),
            b("b19", "👑", .legendary, maxRuns >= 365,          min(maxRuns,365), 365),
            b("b12", "🔮", .legendary, allOtherEarned,          allOtherEarned ? 1:0, 1),
            // ── 신규 b23-b32 ───────────────────────────────────────────────
            b("b23", "🔧", .common,    new.hasCaliber,                           new.hasCaliber ? 1:0, 1),
            b("b24", "🌚", .common,    new.midnightM >= 5,                       min(new.midnightM,5), 5),
            b("b25", "📖", .rare,      new.consecutiveJournalDays >= 7,          min(new.consecutiveJournalDays,7), 7),
            b("b26", "⏳", .rare,      new.longMeasurements >= 25,              min(new.longMeasurements,25), 25),
            b("b27", "🔄", .rare,      new.sameDayDoubleDays >= 10,             min(new.sameDayDoubleDays,10), 10),
            b("b28", "🎭", .epic,      new.hasEmotionSpectrum,                  new.hasEmotionSpectrum ? 1:0, 1),
            b("b29", "💪", .epic,      new.highAmplitudeM >= 5,                 min(new.highAmplitudeM,5), 5),
            b("b30", "🔬", .epic,      new.measuredBPHTypes >= 3,               min(new.measuredBPHTypes,3), 3),
            b("b31", "🍂", .epic,      new.hasAllSeasons,                       min(new.seasonsCount,4), 4),
            b("b32", "🏛️", .legendary, new.hasVintageHistory,                   min(new.vintageCount,5), 5),
        ]
    }

    private var filtered: [Badge] {
        switch filter {
        case .all:    return badges
        case .earned: return badges.filter(\.earned)
        case .locked: return badges.filter { !$0.earned }
        }
    }

    private var seenIds: Set<String> {
        (try? JSONDecoder().decode([String].self, from: Data(seenIdsJSON.utf8))).map { Set($0) } ?? []
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.paper0.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    filterRow
                    grid
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            // 상세 모달
            if let badge = selectedBadge {
                BadgeDetailCardView(badge: badge) {
                    withAnimation(.easeOut(duration: 0.2)) { selectedBadge = nil }
                }
                .transition(.opacity)
                .zIndex(1)
            }
            // 토스트
            if let badge = toastBadge {
                VStack {
                    Spacer()
                    BadgeUnlockToast(badge: badge)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 32)
                }
                .zIndex(2)
            }
        }
        .navigationTitle(String(localized: "badges.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkNewBadges() }
        .onChange(of: badges) { _, newBadges in checkNewBadges(badges: newBadges) }
    }

    // MARK: - Toast

    private func checkNewBadges(badges list: [Badge]? = nil) {
        let current = list ?? badges
        let earnedIds = Set(current.filter(\.earned).map(\.id))
        let newlyEarned = earnedIds.subtracting(seenIds)
        if let data = try? JSONEncoder().encode(Array(earnedIds)),
           let str = String(data: data, encoding: .utf8) { seenIdsJSON = str }
        guard let newId = newlyEarned.first,
              let badge = current.first(where: { $0.id == newId }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { toastBadge = badge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard toastBadge?.id == badge.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastBadge = nil }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        let earned = badges.filter(\.earned).count
        let total  = badges.count
        return HStack {
            Text("\(earned) / \(total) 획득")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.ink0)
            Spacer()
            Text("LV. \(max(1, earned / 3 + 1))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Filter

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(BadgeFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { filter = f }
                } label: {
                    Text(f.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(filter == f ? .white : AppColors.ink0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(filter == f ? AppColors.primaryDeep : AppColors.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Grid (3열)

    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 16
        ) {
            ForEach(filtered) { badge in
                cell(for: badge)
            }
        }
    }

    @ViewBuilder
    private func cell(for badge: Badge) -> some View {
        let cellBody = BadgeCell(badge: badge)

        if badge.earned {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeIn(duration: 0.15)) { selectedBadge = badge }
            } label: { cellBody }
                .buttonStyle(.plain)
        } else {
            cellBody
        }
    }
}

// MARK: - BadgeCell

private struct BadgeCell: View {
    let badge: BadgesView.Badge

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill((badge.earned ? badge.rarity.color : Color(red: 0.85, green: 0.85, blue: 0.87))
                        .opacity(badge.earned ? 0.15 : 0.5))
                    .frame(width: 68, height: 68)
                if badge.earned {
                    Text(badge.emoji)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.62))
                }
            }
            Text(badge.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(badge.earned ? AppColors.ink0 : AppColors.ink3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(badge.earned ? badge.desc : String(localized: "badges.locked"))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.ink3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.paper1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(badge.earned ? badge.rarity.color.opacity(0.25) : AppColors.rule, lineWidth: 1)
        )
    }
}

// MARK: - BadgeDetailCardView (LockIn Focus 스타일)

private struct BadgeDetailCardView: View {
    let badge: BadgesView.Badge
    let onClose: () -> Void

    @State private var rotation: Double = -180
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 18) {
                Text(String(localized: "badges.detail.header"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))

                // 카드
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(
                            colors: badge.rarity.gradientColors,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 220, height: 300)
                        .shadow(color: badge.rarity.color.opacity(0.5), radius: 24, x: 0, y: 12)
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 140, height: 140)
                            Text(badge.emoji)
                                .font(.system(size: 64))
                        }
                        Text(badge.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .lineLimit(2)
                    }
                    .frame(width: 220, height: 300)
                }

                Text(badge.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text(badge.desc)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(action: onClose) {
                    Text(String(localized: "common.close"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.7)) {
                rotation = 0; scale = 1; opacity = 1
            }
        }
    }
}

// MARK: - BadgeUnlockToast

private struct BadgeUnlockToast: View {
    let badge: BadgesView.Badge
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badge.rarity.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(badge.emoji).font(.system(size: 24))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "badges.toast.title"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(badge.rarity.color)
                Text(badge.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.success)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(badge.rarity.color.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { BadgesView() }
        .modelContainer(for: [Watch.self, WatchMeasurement.self, JournalEntry.self, WearLog.self], inMemory: true)
}
