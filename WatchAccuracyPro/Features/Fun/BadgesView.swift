import SwiftData
import SwiftUI

/// 관리자 확인용 — 모든 뱃지를 획득 상태로 표시(override). 끄면 실제 데이터 기준으로 원상복구.
enum BadgeAdminOverride {
    static let key = "ticklab.admin.forceAllBadges"
    static var grantAll: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - BadgesView

struct BadgesView: View {
    // Round 22 (Min): unsorted @Query 4개 — array identity 가 변동 시 .onChange 비결정적 fire.
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    @Query(sort: \WatchMeasurement.timestamp, order: .reverse) private var measurements: [WatchMeasurement]
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var journals: [JournalEntry]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]

    @State private var filter: BadgeFilter = .all
    @State private var selectedBadge: Badge? = nil
    @State private var toastBadge: Badge? = nil
    @State private var community: Community.MyStats? = nil   // Round 172: 커뮤니티 배지 통계(서버).
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
            case .common:    return String(localized: "badges.rarity.common").uppercased()
            case .rare:      return String(localized: "badges.rarity.rare").uppercased()
            case .epic:      return String(localized: "badges.rarity.epic").uppercased()
            case .legendary: return String(localized: "badges.rarity.legendary").uppercased()
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
            let grouped = Dictionary(grouping: wearLogs.filter { $0.watch != nil }, by: { $0.watch!.id })
            return grouped.values.map { logs in
                Set(logs.map { Calendar.current.startOfDay(for: $0.date) }).count
            }.max() ?? 0
        }()
        let maxRuns: Int = {
            let grouped = Dictionary(grouping: measurements.filter { $0.watch != nil }, by: { $0.watch!.id })
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
            // 버그 수정: 저널 0개면 days 가 빈 배열 → 1..<0 잘못된 범위로 크래시. indices.dropFirst 로 안전화.
            for i in days.indices.dropFirst() {
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
        // Round 172 커뮤니티 배지 파라미터 — 서버 통계(미로드면 0) + 로컬(준 좋아요·팔로잉).
        let comm = CommunityBadgeParams(
            postCount: community?.postCount ?? 0,
            likesReceived: community?.likesReceived ?? 0,
            likesGiven: CommunityService.shared.likedPostIDs.count,
            following: CommunityService.shared.followedUIDs.count,
            followers: community?.followerCount ?? 0
        )
        let partial = makeBadges(
            registered: registered, totalM: totalM,
            earlyMorning: earlyMorning, lateNight: lateNight,
            distinctBrands: distinctBrands, journalCount: journalCount,
            longestWear: longestWear, maxRuns: maxRuns,
            hasGMT: hasGMT, hasMoon: hasMoon, hasDiver: hasDiver,
            hasChrono: hasChrono, hasVintage: hasVintage,
            hasCOSCM: hasCOSCM, hasGradeA: hasGradeA, hasPerfectB: hasPerfectB,
            allOtherEarned: false, new: newParams, community: comm
        )
        // b12("모두 획득")는 본인 데이터 배지 기준 — 커뮤니티(b33+) 참여/바이럴은 제외(b12 달성 가능하게).
        let communityIDs: Set<String> = ["b33", "b34", "b35", "b36", "b37", "b38"]
        let allOther = partial.filter { $0.id != "b12" && !communityIDs.contains($0.id) }.allSatisfy(\.earned)
        let computed = makeBadges(
            registered: registered, totalM: totalM,
            earlyMorning: earlyMorning, lateNight: lateNight,
            distinctBrands: distinctBrands, journalCount: journalCount,
            longestWear: longestWear, maxRuns: maxRuns,
            hasGMT: hasGMT, hasMoon: hasMoon, hasDiver: hasDiver,
            hasChrono: hasChrono, hasVintage: hasVintage,
            hasCOSCM: hasCOSCM, hasGradeA: hasGradeA, hasPerfectB: hasPerfectB,
            allOtherEarned: allOther, new: newParams, community: comm
        )
        // 관리자 확인용 override — 전부 획득 상태로 표시(실제 데이터 변경 없음, 끄면 원상복구).
        guard BadgeAdminOverride.grantAll else { return computed }
        return computed.map {
            Badge(id: $0.id, name: $0.name, desc: $0.desc, condition: $0.condition,
                  emoji: $0.emoji, rarity: $0.rarity, earned: true, progress: $0.total, total: $0.total)
        }
    }

    /// Round 172 커뮤니티 배지 파라미터.
    private struct CommunityBadgeParams {
        let postCount: Int      // 내 글 수
        let likesReceived: Int  // 내 글이 받은 좋아요
        let likesGiven: Int     // 내가 누른 좋아요(로컬)
        let following: Int      // 내가 팔로우(로컬)
        let followers: Int      // 나를 팔로우(서버)
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
        allOtherEarned: Bool, new: NewBadgeParams, community comm: CommunityBadgeParams
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
            // ── 커뮤니티 b33-b38 (Round 172) ──────────────────────────────────
            b("b33", "🖼️", .common,    comm.postCount >= 1,        min(comm.postCount,1),     1),
            b("b34", "👍", .common,    comm.likesGiven >= 100,     min(comm.likesGiven,100),  100),
            b("b35", "🔥", .rare,      comm.likesReceived >= 100,  min(comm.likesReceived,100),100),
            b("b36", "📷", .rare,      comm.postCount >= 100,      min(comm.postCount,100),   100),
            b("b37", "🤝", .rare,      comm.following >= 50,       min(comm.following,50),    50),
            b("b38", "📣", .legendary, comm.followers >= 100,      min(comm.followers,100),   100),
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
        // Round 172: 커뮤니티 배지 통계 로드(내 글·받은좋아요·팔로워). 실패/오프라인이면 0 유지.
        .task { if community == nil { community = await CommunityService.shared.fetchMyStats() } }
        .onChange(of: badges) { _, newBadges in checkNewBadges(badges: newBadges) }
    }

    // MARK: - Toast

    private func checkNewBadges(badges list: [Badge]? = nil) {
        // 관리자 override 중에는 토스트·seen 갱신 안 함(실데이터 보존).
        if BadgeAdminOverride.grantAll { return }
        let current = list ?? badges
        let earnedIds = Set(current.filter(\.earned).map(\.id))
        let newlyEarned = earnedIds.subtracting(seenIds)
        // Round 175 (사용자 보고: 진입마다 "첫 게시" 토스트 재등장):
        //   커뮤니티 통계(b33+)는 async 로 늦게 로드 → onAppear 시점 earnedIds 엔 빠져 있음.
        //   earnedIds 로 '덮어쓰면' 이미 본 커뮤니티 배지가 seen 에서 제거돼 재토스트됨.
        //   → union 으로 누적만(절대 제거 안 함).
        let updatedSeen = seenIds.union(earnedIds)
        if let data = try? JSONEncoder().encode(Array(updatedSeen)),
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
            Text(String(format: NSLocalizedString("badges.summary.earned", comment: ""), earned, total))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.ink0)
            Spacer()
            Text(String(format: NSLocalizedString("badges.summary.level", comment: ""), max(1, earned / 3 + 1)))
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
                        .foregroundStyle(filter == f ? AppColors.paper0 : AppColors.ink0)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(filter == f ? AppColors.ink0 : AppColors.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(f.label)
                .accessibilityAddTraits(filter == f ? .isSelected : [])
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
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeIn(duration: 0.15)) { selectedBadge = badge }
            } label: { cellBody }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(badge.name). \(String(localized: "badges.locked")). \(badge.desc)")
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
                    BadgeGlyph(id: badge.id, size: 36, color: badge.rarity.color)
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
    /// Round 171: 닉네임 옆에 장착한 뱃지 이모지. 커뮤니티 게시 시 함께 전송(author_badge).
    @AppStorage("ticklab.profile.equippedBadge") private var equippedBadge: String = ""

    private var isEquipped: Bool { badge.earned && equippedBadge == badge.emoji }

    /// 잠긴 뱃지는 무채색 카드 — 획득 카드와 시각적으로 구분.
    private var cardGradient: [Color] {
        badge.earned ? badge.rarity.gradientColors
                     : [Color(white: 0.46), Color(white: 0.30)]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(String(localized: "common.close"))
                .accessibilityAction(.escape) { onClose() }

            VStack(spacing: 18) {
                // Round 171 (사용자 보고: 잠긴 뱃지 클릭 시 "획득"으로 표시되는 버그):
                // earned/locked 를 명확히 구분. 잠김이면 자물쇠 + 획득 조건 + 진행도.
                Text(String(localized: badge.earned ? "badges.detail.header" : "badges.detail.header.locked"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))

                // 카드
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(
                            colors: cardGradient,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 220, height: 300)
                        .shadow(color: (badge.earned ? badge.rarity.color : Color.black).opacity(0.5), radius: 24, x: 0, y: 12)
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 140, height: 140)
                            if badge.earned {
                                BadgeGlyph(id: badge.id, size: 70, color: .white)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
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

                if badge.earned {
                    Text(badge.desc)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    // 잠김 — 획득 조건 + 진행도.
                    VStack(spacing: 10) {
                        Text(badge.condition.isEmpty ? badge.desc : badge.condition)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        if badge.total > 1 {
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.25))
                                Capsule().fill(.white.opacity(0.85))
                                    .frame(width: 160 * CGFloat(min(1.0, Double(badge.progress) / Double(max(1, badge.total)))))
                            }
                            .frame(width: 160, height: 6)
                            Text("\(badge.progress) / \(badge.total)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }

                // Round 171: 획득한 뱃지는 닉네임 옆에 장착/해제 가능 (커뮤니티 표시).
                if badge.earned {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        equippedBadge = isEquipped ? "" : badge.emoji
                    } label: {
                        Label(
                            String(localized: isEquipped ? "badges.detail.unequip" : "badges.detail.equip"),
                            systemImage: isEquipped ? "checkmark.seal.fill" : "seal"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(badge.rarity.color)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

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
