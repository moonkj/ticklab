import SwiftData
import SwiftUI

/// TickLab v3 Tab 2 — Journal feed.
/// Stories rail + Calendar strip + 3-tab segmented (Grid / Feed / Calendar).
struct JournalFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]

    @State private var viewMode: ViewMode = .feed
    @State private var composing = false

    /// Round 176: RootTabView 가 주입하는 NavigationStack path.
    private let externalPath: Binding<NavigationPath>?
    @State private var localPath = NavigationPath()
    private var pathBinding: Binding<NavigationPath> {
        externalPath ?? $localPath
    }

    init(path: Binding<NavigationPath>? = nil) {
        self.externalPath = path
    }

    enum ViewMode: String, CaseIterable {
        case grid, feed, calendar
        /// String.LocalizationValue + interpolation 가 key lookup 안 되는 버그 — 명시 switch.
        var localizedName: String {
            switch self {
            case .grid:     return String(localized: "journal.view.grid")
            case .feed:     return String(localized: "journal.view.feed")
            case .calendar: return String(localized: "journal.view.calendar")
            }
        }
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    storiesRail
                    calendarStrip
                    modePicker
                    Group {
                        switch viewMode {
                        case .grid:     gridSection
                        case .feed:     feedSection
                        case .calendar: calendarSection
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "journal.title"))
            // Round 138 사용자 요청: 통계처럼 inline 고정 — 스크롤해도 제목 사라지지 않음.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.paper0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Round 72: toolbar text(title) 색상 강제 — system dark mode 에서도 light 톤 유지.
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .sheet(isPresented: $composing) {
                JournalComposerView()
                    .presentationDetents([.large])
            }
            // Round 141 (Hyemi H2): NavigationStack 최상단에 한 번만 등록 — gridSection/feedSection 중복 제거.
            .navigationDestination(for: JournalEntry.self) { entry in
                JournalEntryDetailView(entry: entry)
            }
        }
    }

    // MARK: - Stories rail (per-watch latest entries)
    /// 디자인 SSOT screens-main.jsx JournalFeedView stories rail.
    /// "+ 새 일기" dashed border 카드 + watch silhouette circles (hasEntry 면 gold border).
    /// Round 93: 시계 없을 때 hint message.
    @ViewBuilder
    private var storiesRail: some View {
        if watches.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppColors.info)
                Text(String(localized: "journal.empty.no_watch"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                Spacer()
            }
            .padding(12)
            .background(AppColors.info.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    newEntryCircle
                    ForEach(watches) { watch in
                        storyCircle(for: watch)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private var newEntryCircle: some View {
        Button {
            composing = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            AppColors.rule,
                            style: StrokeStyle(lineWidth: 2, dash: [4])
                        )
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(AppColors.paper2))
                    Image(systemName: "plus")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.ink2)
                }
                Text(String(localized: "journal.compose.cta"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .buttonStyle(.plain)
    }

    private func storyCircle(for watch: Watch) -> some View {
        let hasEntry = entries.contains(where: { $0.watch?.id == watch.id })
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        hasEntry ? AppColors.accent : AppColors.rule,
                        lineWidth: hasEntry ? 2 : 1
                    )
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(AppColors.paper2))
                Group {
                    if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                    } else {
                        WatchSilhouette(watch: watch, size: 44)
                    }
                }
            }
            // Round 133 사용자 요청: 같은 제조사 여러 시계 구분 위해 모델명도 표시.
            VStack(spacing: 1) {
                Text(watch.brand)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(AppColors.ink0)
                Text(watch.model)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundStyle(AppColors.ink2)
            }
            .frame(maxWidth: 70)
        }
    }

    // MARK: - Calendar strip (가로 14일)
    private var calendarStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(daysRange, id: \.self) { day in
                        dayCell(day: day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(today, anchor: .center)
            }
        }
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var daysRange: [Date] {
        let cal = Calendar.current
        return (-7...6).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private func dayCell(day: Date) -> some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: today)
        let hasEntry = entries.contains { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }
        let dayLabel = Calendar.current.component(.day, from: day)
        return VStack(spacing: 4) {
            Text(dayShort(day))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(isToday ? AppColors.accent : AppColors.ink3)
            Text("\(dayLabel)")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(isToday ? AppColors.ink0 : AppColors.ink2)
            Circle()
                .fill(hasEntry ? AppColors.accent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(width: 36, height: 56)
        .background(isToday ? AppColors.accent50 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func dayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f.string(from: date).uppercased()
    }

    // MARK: - Mode picker
    private var modePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.localizedName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(AppColors.accent)
        .padding(.horizontal, 20)
    }

    // MARK: - Grid / Feed / Calendar sections
    private var gridSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(entries) { entry in
                NavigationLink(value: entry) {
                    gridThumb(entry: entry)
                }
            }
        }
        .padding(.horizontal, 20)
        // Round 141 (Hyemi H2): navigationDestination 은 NavigationStack 최상단에 한 번만.
    }

    private func gridThumb(entry: JournalEntry) -> some View {
        ZStack {
            AppColors.paper2
            // Round 172: photoPaths 첫 사진 실제 로드 (이전엔 photo icon placeholder).
            if let stored = entry.photoPaths.first,
               let firstPath = EXIFStripper.resolvePhotoPath(stored),
               let data = try? Data(contentsOf: URL(fileURLWithPath: firstPath)),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let watch = entry.watch {
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    WatchSilhouette(watch: watch, size: 90)
                }
            } else {
                Text(entry.mood.emoji)
                    .font(.system(size: 32))
            }
            // Mood overlay (bottom-left, jsx 매칭). UX 감사: 14→16pt 가독성.
            VStack {
                Spacer()
                HStack {
                    Text(entry.mood.emoji)
                        .font(.system(size: 16))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    Spacer()
                }
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var feedSection: some View {
        VStack(spacing: 16) {
            if entries.isEmpty {
                emptyState
            } else {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) {
                        feedCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        // Round 141 (Hyemi H2): navigationDestination 은 NavigationStack 최상단에 한 번만.
    }

    private func feedCard(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(entry.mood.emoji)
                if let watch = entry.watch {
                    // Round 133: 제조사 + 모델명 함께 표시 (같은 제조사 여러 시계 구분).
                    VStack(alignment: .leading, spacing: 0) {
                        Text(watch.brand)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(AppColors.ink0)
                        Text(watch.model)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.ink2)
                    }
                }
                Spacer()
                Text(entry.timestamp, format: .dateTime.day().month())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
            // Round 172: 사진 있으면 thumbnail 가로 카루셀 (feed 에서도 시각 단서).
            if !entry.photoPaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(entry.photoPaths.prefix(4).enumerated()), id: \.offset) { _, stored in
                            if let path = EXIFStripper.resolvePhotoPath(stored),
                               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                               let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(4)
            }
            if entry.measurementId != nil {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10))
                    Text(String(localized: "journal.has_measurement"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                }
                .foregroundStyle(AppColors.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.accent.opacity(0.5))
            Text(String(localized: "journal.empty.title"))
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "journal.empty.body"))
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.ink2)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date(), format: .dateTime.year().month())
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.ink0)
                .padding(.horizontal, 20)
            calendarGrid
                .padding(.horizontal, 20)
        }
    }

    private var calendarGrid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(days, id: \.self) { day in
                if let day {
                    let entry = entries.first { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }
                    let hasEntry = entry != nil
                    // Round 171: 날짜 tap → 해당 일기 navigation (와이어프레임 Flow Map D).
                    Group {
                        if let entry {
                            NavigationLink(value: entry) {
                                calendarDayCell(day: day, hasEntry: hasEntry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            calendarDayCell(day: day, hasEntry: false)
                        }
                    }
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func calendarDayCell(day: Date, hasEntry: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 13, weight: hasEntry ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(hasEntry ? AppColors.ink0 : AppColors.ink3)
            Circle()
                .fill(hasEntry ? AppColors.accent : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(hasEntry ? AppColors.accent50 : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var monthDays: [Date?] {
        let cal = Calendar.current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let weekday = cal.component(.weekday, from: start) - 1
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: start) {
                days.append(date)
            }
        }
        return days
    }
}
