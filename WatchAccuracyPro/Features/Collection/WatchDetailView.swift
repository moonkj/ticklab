import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct WatchDetailView: View {
    @Bindable var watch: Watch
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Round 176: 대표 시계 토글 시 다른 시계의 isPrimary 해제 위해 전체 watch 목록 필요.
    @Query(sort: \Watch.createdAt, order: .reverse) private var allWatches: [Watch]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]

    @State private var range: TrendRange = .week
    /// Round 29 (Doyoon): HistoryRow tap 시 편집할 측정. nil 이면 sheet 닫힘.
    @State private var editingMeasurement: WatchMeasurement?
    /// Round 125: SpecCard 작성 sheet.
    @State private var composingSpecCard: Bool = false
    /// Round 118 (검토B High): 이 시계 태그된 일기 직접 작성.
    @State private var composingJournal: Bool = false
    /// Round 125 (성능 H10): journal/service fetch 캐시 — body 재계산마다 DB 스캔 방지.
    @State private var cachedJournalEntries: [JournalEntry] = []
    @State private var cachedServiceLogs: [ServiceLog] = []
    /// Round 20 (Sora): isWornToday body 안 3회 fetch 차단 — wear toggle 시점에 갱신.
    @State private var cachedWornToday: Bool = false
    /// Round 170: 측정 이력 삭제 확인 (전체 삭제용).
    @State private var showDeleteAllMeasurementsAlert = false
    @State private var historyExpanded = false
    private static let historyPageSize = 8
    /// 일기 탭 더보기 토글 — 첫 진입 시 5개만 표시.
    @State private var journalExpanded = false
    private static let journalPageSize = 5
    /// 서비스 로그 타임라인 더보기 토글 — 첫 진입 시 5개만 표시.
    @State private var serviceLogExpanded = false
    private static let serviceLogPageSize = 5
    /// Round 170: 단일 측정 삭제 확인.
    @State private var measurementToDelete: WatchMeasurement?
    /// Round 173: 시계 정보 편집 sheet + 삭제 확인 alert.
    @State private var editing: Bool = false
    @State private var deleteAlert: Bool = false
    /// Round 175: 알림 권한 거부 안내 alert.
    @State private var showNotificationPermissionAlert: Bool = false
    /// Round 129: ServiceLog composer sheet.
    @State private var composingServiceLog: Bool = false
    /// Round 144: 시계 이미지 변경 — action sheet + photo picker / camera.
    @State private var showingPhotoSourceSheet: Bool = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera: Bool = false
    /// Round 133 BUG FIX: confirmationDialog 안 PhotosPicker 가 sheet 안 띄우는 SwiftUI 버그 우회.
    /// dialog 닫힌 후 별도 boolean 으로 PhotosPicker 트리거.
    @State private var showingPhotoLibrary: Bool = false
    /// Round 94 (정수민 Critical #2): 사진 풀스크린 줌.
    @State private var showingFullscreenPhoto: Bool = false
    /// Round 46: 디자인 SSOT screens-detail.jsx WatchDetailView 의 3 탭 (measure/journal/service).
    @State private var detailTab: DetailTab = .measure
    enum DetailTab: String, CaseIterable { case measure, journal, service }

    typealias TrendRange = WatchDetailTrendRange

    // Round 104 (Swift Critical): DateFormatter 는 생성 비용이 높으므로 static 캐시.
    private static let purchaseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private var movement: Movement? {
        watch.caliber.flatMap { MovementDatabase.shared.movement(id: $0) }
    }
    // Round 116 (성능 H1): 매 body 마다 sort O(N log N) 방지 — @State 캐시 + onChange 갱신.
    @State private var sortedMeasurements: [WatchMeasurement] = []
    private var measurements: [WatchMeasurement] { sortedMeasurements }
    private var lastMeasurement: WatchMeasurement? { sortedMeasurements.first }
    private var filtered: [WatchMeasurement] {
        let cutoff = range.cutoffDate
        return sortedMeasurements.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                actionsSection
                statusStripSection
                storyCard
                careSection
                detailTabBar
                switch detailTab {
                case .measure:
                    measureTab
                case .journal:
                    journalTab
                case .service:
                    serviceTab
                }
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .onAppear {
            sortedMeasurements = watch.measurements.sorted(by: { $0.timestamp > $1.timestamp })
            refreshJournalAndServiceCache()
            // Round 20 (Sora): isWornToday body 안 fetch 차단용 캐시 초기화.
            cachedWornToday = WearLogService.isWornToday(watch, in: modelContext)
        }
        .onChange(of: watch.measurements.count) { _, _ in
            sortedMeasurements = watch.measurements.sorted(by: { $0.timestamp > $1.timestamp })
        }
        .task(id: detailTab) { refreshJournalAndServiceCache() }
        .onChange(of: composingJournal) { _, isPresented in if !isPresented { refreshJournalAndServiceCache() } }
        .onChange(of: composingServiceLog) { _, isPresented in if !isPresented { refreshJournalAndServiceCache() } }
        .sheet(item: $editingMeasurement) { m in
            MeasurementNoteEditor(measurement: m) {
                try? modelContext.save()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $composingServiceLog) {
            ServiceLogComposerView(watch: watch)
        }
        // Round 118: 이 시계 직접 일기 작성.
        .sheet(isPresented: $composingJournal) {
            JournalComposerView(defaultWatch: watch)
        }
        // Round 133: confirmationDialog 가 iOS 26 에서 중앙 popover + 라이브러리 trigger 안 되는 버그로
        // 커스텀 PhotoSourceSheet 로 교체. 라이브러리/카메라 sheet 는 dialog 닫힌 후 별도 트리거.
        .sheet(isPresented: $showingPhotoSourceSheet) {
            PhotoSourceSheet(
                title: String(localized: "watch.photo.dialog.title"),
                allowRemove: watch.photoData != nil,
                onLibrary: {
                    showingPhotoSourceSheet = false
                    // dismiss 끝나고 라이브러리 trigger.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingPhotoLibrary = true
                    }
                },
                onCamera: {
                    showingPhotoSourceSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingCamera = true
                    }
                },
                onRemove: {
                    showingPhotoSourceSheet = false
                    watch.photoData = nil
                    // Round 147 (Min C1): photo 변경/제거 시 NSCache stale 방지.
                    PhotoCache.invalidate(id: watch.id)
                    try? modelContext.save()
                }
            )
        }
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $photoItem, matching: .images)
        .sheet(isPresented: $showingCamera) {
            CameraImagePicker(imageData: Binding(
                get: { watch.photoData },
                set: { newData in
                    if let newData {
                        watch.photoData = newData
                        // Round 147 (Min C1): photo 변경 시 NSCache stale 방지.
                        PhotoCache.invalidate(id: watch.id)
                        // Round (3-1): 즉시 background prefetch — 다음 hero render main thread spike 회피.
                        PhotoCache.prefetch(for: watch.id, data: newData)
                        try? modelContext.save()
                    }
                }
            ))
            .ignoresSafeArea()
        }
        // Round 94 (정수민 #2): 풀스크린 줌 viewer.
        .fullScreenCover(isPresented: $showingFullscreenPhoto) {
            FullscreenPhotoViewer(
                imageData: watch.photoData,
                onDismiss: { showingFullscreenPhoto = false }
            )
        }
        .onChange(of: photoItem) { _, new in
            Task {
                guard let new,
                      let raw = try? await new.loadTransferable(type: Data.self) else { return }
                let stripped = EXIFStripper.strippedJPEG(from: raw)
                await MainActor.run {
                    watch.photoData = stripped
                    // Round 147 (Min C1): NSCache stale 방지.
                    PhotoCache.invalidate(id: watch.id)
                    // Round (3-1): background prefetch.
                    PhotoCache.prefetch(for: watch.id, data: stripped)
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $composingSpecCard) {
            // Round 126: 기존 카드 있으면 편집, 없으면 신규.
            let existingCard: SpecCard? = {
                let watchId = watch.id
                let desc = FetchDescriptor<SpecCard>(predicate: #Predicate { $0.watch?.id == watchId })
                return (try? modelContext.fetch(desc))?.first
            }()
            SpecCardComposerView(watch: watch, existing: existingCard)
        }
        .navigationTitle(watch.model)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 사용자 보고 fix: iPhone SE 에서 3 toolbar slot + 긴 모델명 → title 잘림. favorite 을 menu 안으로 이동.
            //   (favorite 은 컬렉션 카드 contextMenu 에서도 접근 가능해서 toolbar 중복 제거 안전.)
            // Round 121: "오늘 착용" toggle (디자인 Journey axis).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    WearLogService.toggleToday(watch, in: modelContext)
                    // Round 20: cache 갱신 — 다음 body 호출이 fetch 안 하도록.
                    cachedWornToday = WearLogService.isWornToday(watch, in: modelContext)
                } label: {
                    Image(systemName: cachedWornToday ? "checkmark.seal.fill" : "checkmark.seal")
                        .foregroundStyle(cachedWornToday ? AppColors.accent : AppColors.ink2)
                }
                .accessibilityLabel(String(localized: "a11y.wear_today"))
                .accessibilityValue(String(localized: cachedWornToday ? "a11y.value.worn" : "a11y.value.not_worn"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        watch.isFavorite.toggle()
                    } label: {
                        Label(String(localized: watch.isFavorite ? "watch.menu.favorite.remove" : "watch.menu.favorite.add"),
                              systemImage: watch.isFavorite ? "star.fill" : "star")
                    }
                    // Round 173: 시계 정보 편집 / 삭제.
                    Button {
                        editing = true
                    } label: {
                        Label(String(localized: "watch.menu.edit"), systemImage: "pencil")
                    }
                    // Round 125: SpecCard 생성.
                    Button {
                        composingSpecCard = true
                    } label: {
                        Label(String(localized: "menu.speccard.create"), systemImage: "rectangle.stack.badge.plus")
                    }
                    if !watch.measurements.isEmpty {
                        let payload = DataExportService.export(watch: watch, format: .csv)
                        if let url = payload.tempURL {
                            ShareLink(item: url) {
                                Label(String(localized: "settings.export.action"),
                                      systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        deleteAlert = true
                    } label: {
                        Label(String(localized: "watch.menu.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AppColors.ink2)
                }
                .accessibilityLabel(String(localized: "a11y.more_actions"))
            }
        }
        .sheet(isPresented: $editing) {
            AddWatchView(existing: watch)
        }
        .alert(String(localized: "watch.delete.confirm.title"), isPresented: $deleteAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) {
                let context = modelContext
                watch.deleteCascade(in: context)
                try? context.save()
                dismiss()
            }
        } message: {
            Text(String(localized: "watch.delete.confirm.body"))
        }
        // Round 175: 알림 권한 거부 안내.
        .alert(
            String(localized: "notification.permission.denied.title"),
            isPresented: $showNotificationPermissionAlert
        ) {
            Button(String(localized: "notification.permission.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "common.done"), role: .cancel) {}
        } message: {
            Text(String(localized: "notification.permission.denied.body"))
        }
    }

    // MARK: - Cache refresh (Round 125)
    private func refreshJournalAndServiceCache() {
        let watchId = watch.id
        cachedJournalEntries = (try? modelContext.fetch(
            FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        ))?.filter { $0.watch?.id == watchId } ?? []
        let svcDesc = FetchDescriptor<ServiceLog>(
            predicate: #Predicate { $0.watch?.id == watchId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        cachedServiceLogs = (try? modelContext.fetch(svcDesc)) ?? []
    }

    // MARK: - Hero

    private var heroHeader: some View {
        // Round 73: ZStack frame 명시 + 카메라 버튼 .overlay(alignment:topTrailing) 로 위치 고정.
        // 이전 Color.clear tap 이 button 위 덮어 클릭 안 되던 문제 + ZStack(.bottomLeading) 으로 위치 어긋남.
        ZStack(alignment: .bottomLeading) {
            // 1) photo / silhouette background — 전체 영역.
            Group {
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [AppColors.primaryDeep, AppColors.primary700],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        WatchSilhouette(watch: watch, size: 220)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()
            .contentShape(Rectangle())
            // Round 94 (정수민 #2): 사진 있으면 풀스크린 줌, 없으면 source sheet.
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                if watch.photoData != nil {
                    showingFullscreenPhoto = true
                } else {
                    showingPhotoSourceSheet = true
                }
            }
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.6)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(watch.brand.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.85))
                // Round 90 (정수민): nickname 있으면 별명을 큰 타이틀, model 은 sub. 없으면 기존대로.
                if let nick = watch.nickname?.trimmingCharacters(in: .whitespaces), !nick.isEmpty {
                    Text(nick)
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(watch.model)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                } else {
                    Text(watch.model)
                        .font(.system(size: 32, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if let ref = watch.referenceNumber?.trimmingCharacters(in: .whitespaces), !ref.isEmpty {
                    Text(String(format: String(localized: "watch.ref_label"), ref))
                        .font(.system(size: 10.5, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if let movement {
                    Text("\(movement.id) · \(movement.bph) BPH")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.top, 2)
                }
                // 페르소나 (정수민) 피드백: 구매일 입력 받지만 detail 어디에도 표시 안 됨.
                // hero header 에 한 줄 노출 — 감정 가치 hook.
                if let purchaseDate = watch.purchaseDate {
                    Text(String(format: NSLocalizedString("watch.owned_since", comment: ""),
                                WatchDetailView.purchaseDateFormatter.string(from: purchaseDate)))
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 1)
                }
            }
            .padding(22)
        }
        .frame(height: 280)
        .clipped()
        // Round 73: 카메라 버튼 — overlay 로 위치 고정 + topTrailing 정렬. ZStack 내부 충돌 해결.
        .overlay(alignment: .topTrailing) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showingPhotoSourceSheet = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(String(localized: "a11y.change_photo"))
        }
    }

    // MARK: - Latest

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "watch.section.latest"), number: "01")
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if let last = lastMeasurement {
                VStack(spacing: 0) {
                    // Round 170: amplitude cell 제거 — 마이크 기반 신뢰성 낮음, 모든 화면 일관.
                    MetricGrid(cells: [
                        MetricBadge(
                            label: String(localized: "watch.label.rate"),
                            value: formatRate(last.rateSecondsPerDay),
                            unit: String(localized: "unit.seconds_per_day"),
                            tone: rateColorTone(last.rateSecondsPerDay),
                            big: true
                        ),
                        MetricBadge(
                            label: String(localized: "watch.label.beat_error"),
                            value: String(format: "%.2f", last.beatErrorMs),
                            unit: "ms",
                            tone: last.beatErrorMs < 0.5 ? .success : .warning,
                            big: true
                        ),
                        MetricBadge(
                            label: String(localized: "watch.label.position"),
                            value: positionShort(last.metadata.position),
                            big: true
                        )
                    ])
                    HStack {
                        ConfidenceBadge(score: last.confidenceScore, compact: true)
                        Spacer()
                        Text(formatDate(last.timestamp))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppColors.ink3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(AppColors.rule).frame(height: 1)
                    }
                }
                .background(AppColors.paper0)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
                // Round 63: COSC bar 추가 (디자인 SSOT screens-detail.jsx WatchDetailView measure tab).
                COSCBar(rate: last.rateSecondsPerDay)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            } else {
                HelpCard(
                    icon: "stopwatch",
                    title: String(localized: "watch.no_readings.title"),
                    body: String(localized: "watch.no_readings.body")
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Actions

    // MARK: - Round 46 tabs (디자인 SSOT screens-detail.jsx WatchDetailView)

    private var detailTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { t in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.2)) { detailTab = t }
                } label: {
                    VStack(spacing: 6) {
                        Text(label(for: t))
                            .font(.system(size: 15, weight: detailTab == t ? .semibold : .regular))
                            .foregroundStyle(detailTab == t ? AppColors.ink0 : AppColors.ink2)
                        // Round 170: underline 3 → 4pt — active state 가시성 향상.
                        Rectangle()
                            .fill(detailTab == t ? AppColors.primaryDeep : Color.clear)
                            .frame(height: 4)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.rule).frame(height: 1)
        }
    }

    private func label(for tab: DetailTab) -> String {
        switch tab {
        case .measure: return String(localized: "watchdetail.tab.measure")
        case .journal: return String(localized: "watchdetail.tab.journal")
        case .service: return String(localized: "watchdetail.tab.service")
        }
    }

    /// Measure tab — 기존 sections 모음.
    /// Round 138 (사용자 요청): 쿼츠 시계는 측정 관련 모두 숨김 + BatteryMonitorCard 노출.
    @ViewBuilder
    private var measureTab: some View {
        if watch.movementType == .quartz {
            QuartzBatteryCard(watch: watch)
        } else {
            latestSection
            trendSection
            if preferences.userMode == .pro, let movement {
                specsSection(movement: movement)
            }
            if !measurements.isEmpty { historySection }
        }
    }

    /// Round 91: 이 시계와 link 된 JournalEntry 표시.
    /// Round 125 (성능 H10): @State 캐시 사용 — body 재계산마다 fetch 방지.
    @ViewBuilder
    private var journalTab: some View {
        let entries = cachedJournalEntries
        if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                Text(String(localized: "watch.journal.empty.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(String(localized: "watch.journal.empty.hint"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                // Round 118 (검토B High): 빈 상태에서 바로 작성 진입.
                Button {
                    composingJournal = true
                } label: {
                    Label(String(localized: "watch.journal.compose"), systemImage: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        } else {
            let displayCount = journalExpanded ? entries.count : min(Self.journalPageSize, entries.count)
            let hasMore = entries.count > Self.journalPageSize
            VStack(spacing: 10) {
                ForEach(Array(entries.prefix(displayCount))) { entry in
                    NavigationLink {
                        JournalEntryDetailView(entry: entry)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.mood.emoji).font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppDateFormat.fullDate(entry.timestamp))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(AppColors.ink2)
                                if !entry.body.isEmpty {
                                    Text(entry.body)
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.ink0)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.ink3)
                        }
                        .padding(14)
                        .background(AppColors.paper1)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                if hasMore {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { journalExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(journalExpanded
                                 ? String(localized: "common.collapse")
                                 : String(format: NSLocalizedString("common.show_more_count", comment: ""), entries.count - Self.journalPageSize))
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: journalExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// 사용자 요청: 다음 오버홀 권장일 표시. quartz 제외.
    @ViewBuilder
    private var overhaulDueRow: some View {
        if watch.movementType != .quartz, preferences.overhaulReminderEnabled {
            let lastDate = NotificationService.lastOverhaulDate(for: watch, in: modelContext) ?? watch.createdAt
            if let dueDate = Calendar.current.date(byAdding: .year, value: preferences.overhaulReminderYears, to: lastDate) {
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
                let isOverdue = daysLeft < 0
                HStack(spacing: 12) {
                    Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver")
                        .font(.system(size: 18))
                        .foregroundStyle(isOverdue ? AppColors.warning : AppColors.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "watch.overhaul.next_due"))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(AppColors.ink2)
                        Text(AppDateFormat.fullDate(dueDate))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isOverdue ? AppColors.warning : AppColors.ink0)
                        Text(isOverdue
                             ? String(format: NSLocalizedString("watch.overhaul.overdue_days", comment: ""), abs(daysLeft))
                             : String(format: NSLocalizedString("watch.overhaul.remaining_days", comment: ""), daysLeft))
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.ink3)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    /// Round 129 fix: 실제 ServiceLog @Model 사용 + ServiceLogComposer 진입.
    /// Round 125 (성능 H10): @State 캐시 사용.
    @ViewBuilder
    private var serviceTab: some View {
        let logs = cachedServiceLogs
        VStack(alignment: .leading, spacing: 0) {
            overhaulDueRow
            if logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.accent.opacity(0.5))
                    Text(String(localized: "watch.service.empty.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "watch.service.empty.body"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            } else {
                let displayCount = serviceLogExpanded ? logs.count : min(Self.serviceLogPageSize, logs.count)
                let hasMore = logs.count > Self.serviceLogPageSize
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(AppColors.rule)
                        .frame(width: 2)
                        .padding(.leading, 18)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(logs.prefix(displayCount))) { log in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle().fill(AppColors.paper1).frame(width: 22, height: 22)
                                    Circle().stroke(AppColors.accent, lineWidth: 2).frame(width: 22, height: 22)
                                    Image(systemName: iconFor(log.type))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(AppColors.accentDark)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppDateFormat.fullDate(log.timestamp))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .tracking(0.5)
                                        .foregroundStyle(AppColors.ink2)
                                    Text(log.type.localizedName + (log.serviceCenter.isEmpty ? "" : " (\(log.serviceCenter))"))
                                        .font(.system(size: 15))
                                        .foregroundStyle(AppColors.ink0)
                                    if !log.notes.isEmpty {
                                        Text(log.notes)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColors.ink2)
                                    }
                                }
                            }
                        }
                        if hasMore {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { serviceLogExpanded.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(serviceLogExpanded
                                         ? String(localized: "common.collapse")
                                         : String(format: NSLocalizedString("common.show_more_count", comment: ""), logs.count - Self.serviceLogPageSize))
                                        .font(.system(size: 13, weight: .semibold))
                                    Image(systemName: serviceLogExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.ink2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.leading, 36)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            Button {
                composingServiceLog = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(String(localized: "watch.service.add"))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // Round 125: serviceLogs 제거 — cachedServiceLogs (@State) 사용으로 전환.

    private func iconFor(_ type: ServiceType) -> String {
        switch type {
        case .fullOverhaul, .partialService: return "wrench.adjustable"
        case .checkup: return "checkmark.seal"
        case .waterTest: return "drop"
        case .batteryReplace: return "battery.100"
        case .crystalReplace: return "circle"
        case .crownGasket: return "gear"
        case .bracelet: return "link"
        case .other: return "tag"
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            // Round 138 사용자 요청: 쿼츠 시계는 측정 무의미 — 측정/장기측정 버튼 숨김.
            if watch.movementType != .quartz {
                NavigationLink {
                    MeasurementView(watch: watch, preferences: preferences)
                } label: {
                    PrimaryButton(String(localized: "measurement.button.start"), icon: "mic") {}
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, watch.movementType == .quartz ? 0 : 14)
    }

    // MARK: - Status strip (Round 176, 사용자 UX 요청)

    /// 대표 시계 / 오늘 착용 토글을 시계 상세 본문에 명시. 기존엔 toolbar 의 작은 아이콘만 있어 사용자가 못 찾음.
    /// 두 카드를 가로 배치, 활성 상태는 색상으로 즉시 구분.
    private var statusStripSection: some View {
        let worn = cachedWornToday  // Round 20 (Sora): body 안 fetch 제거 — onAppear 에서 set.
        return HStack(spacing: 10) {
            // 대표 시계 토글
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                togglePrimary()
            } label: {
                statusCard(
                    icon: watch.isPrimary ? "star.fill" : "star",
                    title: watch.isPrimary
                        ? String(localized: "watch.is_primary")
                        : String(localized: "watch.set_as_primary"),
                    subtitle: watch.isPrimary
                        ? String(localized: "watch.unset_primary.hint")
                        : String(localized: "watch.set_as_primary.hint"),
                    active: watch.isPrimary
                )
            }
            .buttonStyle(.plain)

            // 오늘 착용 토글
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                WearLogService.toggleToday(watch, in: modelContext)
                // 사용자 보고 fix: 토글 후 cachedWornToday 가 stale → 즉시 재계산.
                cachedWornToday = WearLogService.isWornToday(watch, in: modelContext)
            } label: {
                statusCard(
                    icon: worn ? "checkmark.seal.fill" : "checkmark.seal",
                    title: worn
                        ? String(localized: "watch.worn_today")
                        : String(localized: "watch.log_wear_today"),
                    subtitle: worn
                        ? String(localized: "watch.worn_today.hint")
                        : String(localized: "watch.log_wear_today.hint"),
                    active: worn
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func statusCard(icon: String, title: String, subtitle: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? AppColors.accent : AppColors.ink2)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? AppColors.accent : AppColors.ink0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(active ? AppColors.accent50 : AppColors.paper1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? AppColors.accentLight : AppColors.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 대표 시계 토글. 다른 시계의 isPrimary 는 false 로 reset — 컬렉션 내 1개만 true 보장.
    private func togglePrimary() {
        if watch.isPrimary {
            watch.isPrimary = false
        } else {
            for w in allWatches where w.id != watch.id && w.isPrimary {
                w.isPrimary = false
            }
            watch.isPrimary = true
        }
        try? modelContext.save()
    }

    // MARK: - Story (Round 90, 정수민): personalisation 카드.
    // Round 118 (정수민 M3): 비어있을 때 편집 prompt.

    @ViewBuilder
    private var storyCard: some View {
        let story = watch.story?.trimmingCharacters(in: .whitespaces) ?? ""
        if !story.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.accent)
                    Text(String(localized: "watch.story.label"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.ink2)
                }
                Text(story)
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundStyle(AppColors.ink0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.paper1)
            .overlay(Rectangle().fill(AppColors.accent).frame(width: 3), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 14)
        } else {
            Button { editing = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.accent)
                    Text(String(localized: "watch.story.empty_prompt"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                }
                .padding(14)
                .background(AppColors.paper1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    // MARK: - Care (Tamagotchi mood + manual winding + quartz battery)

    @ViewBuilder
    private var careSection: some View {
        let status = WatchMoodService.status(of: watch, in: modelContext)
        VStack(spacing: 8) {
            moodCard(status)
            if watch.movementType == .manual {
                windReminderCard
            }
            // Round 138 사용자 요청: 쿼츠 batteryCard 는 측정 탭의 QuartzBatteryCard 와 중복 → 제거.
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func moodCard(_ status: WatchMoodService.Status) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(status.mood.emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 4) {
                Text(status.mood.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                if let days = status.daysSinceInteraction {
                    Text(String(format: NSLocalizedString("watch.mood.last_active", comment: ""), days, status.mood.energy))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink2)
                } else {
                    Text(String(localized: "watch.mood.empty"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink2)
                }
                ProgressView(value: Double(status.mood.energy), total: 100)
                    .tint(AppColors.accent)
                    .frame(height: 4)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.accent50)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accentLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var windReminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(AppColors.primaryDeep)
                Text(String(localized: "watch.wind.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { watch.windReminderEnabled },
                    set: { newValue in
                        watch.windReminderEnabled = newValue
                        try? modelContext.save()
                        if newValue {
                            // Round 175: 권한 거부 상태면 안내 alert.
                            Task {
                                let status = await NotificationService.authorizationStatus()
                                if status == .denied {
                                    await MainActor.run { showNotificationPermissionAlert = true }
                                }
                            }
                            NotificationService.scheduleWindReminder(for: watch)
                        } else {
                            NotificationService.cancelWindReminder(for: watch)
                        }
                    }
                ))
                .labelsHidden()
            }
            if watch.windReminderEnabled {
                DatePicker(String(localized: "settings.random_pick.time"),
                           selection: Binding(
                            get: {
                                Calendar.current.date(bySettingHour: watch.windReminderHour,
                                                       minute: watch.windReminderMinute,
                                                       second: 0,
                                                       of: Date()) ?? Date()
                            },
                            set: { newDate in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                watch.windReminderHour = comps.hour ?? 9
                                watch.windReminderMinute = comps.minute ?? 0
                                try? modelContext.save()
                                NotificationService.scheduleWindReminder(for: watch)
                            }
                           ),
                           displayedComponents: .hourAndMinute)
                .font(.system(size: 13))
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "battery.50")
                    .foregroundStyle(AppColors.primaryDeep)
                Text(String(localized: "watch.battery.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { watch.batteryReminderEnabled },
                    set: { newValue in
                        watch.batteryReminderEnabled = newValue
                        try? modelContext.save()
                        if newValue {
                            Task {
                                let status = await NotificationService.authorizationStatus()
                                if status == .denied {
                                    await MainActor.run { showNotificationPermissionAlert = true }
                                }
                            }
                            NotificationService.scheduleBatteryReminder(for: watch)
                        } else {
                            NotificationService.cancelBatteryReminder(for: watch)
                        }
                    }
                ))
                .labelsHidden()
            }
            DatePicker(String(localized: "watch.battery.last_replaced"),
                       selection: Binding(
                        get: { watch.batteryLastReplaced ?? Date() },
                        set: { newDate in
                            watch.batteryLastReplaced = newDate
                            try? modelContext.save()
                            if watch.batteryReminderEnabled {
                                NotificationService.scheduleBatteryReminder(for: watch)
                            }
                        }
                       ),
                       displayedComponents: .date)
            .font(.system(size: 13))

            // Round 138 사용자 요청: 예상수명 +/- 버튼 제거 — 캘리버 기본값 사용 (수정은 측정 후 자동).
            Text(String(format: NSLocalizedString("watch.battery.life_months", comment: ""), watch.batteryExpectedLifeMonths))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)

            if let due = watch.batteryNextDue {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(String(format: NSLocalizedString("watch.battery.due_date", comment: ""),
                                AppDateFormat.fullDate(due)))
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(AppColors.ink2)
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowLabel(text: String(localized: "watch.section.trend"), number: "02")
                Spacer()
                segmentedRange
            }
            .padding(.horizontal, 20)
            VStack(spacing: 0) {
                TrendChartView(measurements: filtered, range: range)
                    .id(range)  // Round 170: range 변경 시 차트 강제 reload.
                    .frame(height: 130)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                Divider().background(AppColors.rule)
                let stats = computeStats(filtered)
                HStack {
                    StatBlock(label: String(localized: "watch.stat.mean"),
                              value: stats.mean, unit: "s/d")
                    StatBlock(label: String(localized: "watch.stat.deviation"),
                              value: stats.deviation, unit: "s/d")
                    StatBlock(label: String(localized: "watch.stat.best"),
                              value: stats.best, unit: "s/d")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(AppColors.paper0)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }

    // Round 170 (사용자 보고: range 버튼 무반응):
    // 이전엔 nested ScrollView 안 Button — 부모 ScrollView 와 gesture 충돌로 tap 안 먹음.
    // ScrollView wrap 제거 (5 옵션 정도면 SE 375pt 에서도 fit) + buttonStyle(.plain) 명시.
    private var segmentedRange: some View {
        HStack(spacing: 0) {
            ForEach(TrendRange.allCases, id: \.self) { r in
                let selected = range == r
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.18)) { range = r }
                } label: {
                    Text(r.localizedLabel)
                        .font(.system(size: 11, weight: selected ? .bold : .medium, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(selected ? Color.white : AppColors.ink2)
                        .background(selected ? AppColors.ink0 : .clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(r.accessibilityLabel)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppColors.paper1)
        .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
        .clipShape(Capsule())
    }

    // MARK: - Specs (expert)

    private func specsSection(movement: Movement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "watch.info.movement_specs"), number: "03")
                .padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    SpecRow(label: String(localized: "watch.spec.caliber"), value: movement.id)
                    SpecRow(label: String(localized: "watch.spec.bph"),
                            value: "\(movement.bph)")
                    // Round 86 (이재현 H6): liftAngleOverride 가 있으면 워치메이커 측정값 우선.
                    SpecRow(label: String(localized: "watch.spec.lift_angle"),
                            value: "\(Int(watch.liftAngleOverride ?? movement.liftAngleDegrees))°")
                    SpecRow(label: String(localized: "watch.spec.escapement"),
                            value: movement.escapement.rawValue)
                }
                if !movement.shouldDisplayAmplitude {
                    // 사용자 보고 fix: 이전엔 amplitude hide 시 무조건 coaxial 카피 → IWC swissLever
                    //   medium confidence 시계도 "코액시얼" 안내가 떠서 오해. escapement 별 분기.
                    let isCoaxial = movement.escapement == .coAxial
                    HelpCard(
                        icon: "info.circle",
                        title: String(localized: isCoaxial
                                      ? "movement.reliability.coaxial.title"
                                      : "movement.reliability.generic.title"),
                        body: String(localized: isCoaxial
                                     ? "movement.reliability.coaxial.notice"
                                     : "movement.reliability.generic.notice")
                    )
                }
            }
            .padding(14)
            .background(AppColors.paper0)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowLabel(
                    text: String(format: NSLocalizedString("watch.history.runs", comment: ""), measurements.count),
                    number: preferences.userMode == .pro && movement != nil ? "04" : "03"
                )
                Spacer()
                // Round 170: 전체 측정 이력 삭제 버튼 — touch target 44pt+.
                Button {
                    showDeleteAllMeasurementsAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                        Text(String(localized: "watch.history.deleteAll.confirm"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppColors.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.danger.opacity(0.08))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            let displayCount = historyExpanded ? measurements.count : min(Self.historyPageSize, measurements.count)
            let hasMore = measurements.count > Self.historyPageSize
            LazyVStack(spacing: 0) {
                ForEach(Array(measurements.prefix(displayCount).enumerated()), id: \.element.id) { idx, m in
                    HistoryRow(
                        measurement: m,
                        isLast: idx == displayCount - 1 && (!hasMore || historyExpanded),
                        onTap: { editingMeasurement = m },
                        onDelete: { measurementToDelete = m }
                    )
                }
                if hasMore {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { historyExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(historyExpanded
                                 ? String(localized: "watch.history.collapse")
                                 : String(format: NSLocalizedString("watch.history.showMore", comment: ""), measurements.count - Self.historyPageSize))
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppColors.paper0)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
        .alert(
            String(localized: "watch.history.deleteAll.title"),
            isPresented: $showDeleteAllMeasurementsAlert
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "watch.history.deleteAll.confirm"), role: .destructive) {
                deleteAllMeasurements()
            }
        } message: {
            Text(String(format: NSLocalizedString("watch.history.deleteAll.message", comment: ""), measurements.count))
        }
        .alert(
            String(localized: "watch.history.deleteOne.title"),
            isPresented: Binding(
                get: { measurementToDelete != nil },
                set: { if !$0 { measurementToDelete = nil } }
            )
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {
                measurementToDelete = nil
            }
            Button(String(localized: "common.delete"), role: .destructive) {
                if let m = measurementToDelete { deleteMeasurement(m) }
                measurementToDelete = nil
            }
        } message: {
            Text(String(localized: "watch.history.deleteOne.message"))
        }
    }

    /// Round 170: 측정 1건 삭제 — SwiftData context 에서 제거 + watch.measurements relationship 갱신.
    private func deleteMeasurement(_ m: WatchMeasurement) {
        modelContext.delete(m)
        try? modelContext.save()
        sortedMeasurements = watch.measurements.sorted(by: { $0.timestamp > $1.timestamp })
        WatchMoodService.invalidate(for: watch)
    }

    /// Round 170: 이 시계의 모든 측정 삭제.
    private func deleteAllMeasurements() {
        for m in watch.measurements {
            modelContext.delete(m)
        }
        try? modelContext.save()
        sortedMeasurements = []
        WatchMoodService.invalidate(for: watch)
    }

    // MARK: - Helpers

    private func rateColorTone(_ rate: Double) -> MetricBadge.Tone {
        let abs = abs(rate)
        if abs <= 6 { return .success }
        if abs <= 20 { return .warning }
        return .danger
    }
    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: d).uppercased()
    }
    private func positionShort(_ p: Position) -> String {
        let key: String
        switch p {
        case .dialUp:      key = "position.dialup_short"
        case .dialDown:    key = "position.dialdown_short"
        case .crownLeft:   key = "position.crownleft_short"
        case .crownRight:  key = "position.crownright_short"
        case .crownUp:     key = "position.pendantup_short"
        case .crownDown:   key = "position.pendantdown_short"
        case .unknown:     return "—"
        }
        return String(localized: String.LocalizationValue(key))
    }
    private func computeStats(_ ms: [WatchMeasurement]) -> (mean: String, deviation: String, best: String) {
        guard !ms.isEmpty else { return ("—", "—", "—") }
        let rates = ms.map { $0.rateSecondsPerDay }
        let mean = rates.reduce(0, +) / Double(rates.count)
        let variance = rates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rates.count)
        let stdev = sqrt(variance)
        let best = rates.map { (rate: $0, abs: abs($0)) }.min(by: { $0.abs < $1.abs })?.rate ?? 0
        let fmt: (Double) -> String = { ($0 >= 0 ? "+" : "") + String(format: "%.1f", $0) }
        return (fmt(mean), String(format: "%.1f", stdev), fmt(best))
    }
}

// MARK: - History row

// Round (잔여 분할): HistoryRow, StatBlock, WatchMeasurement Identifiable conformance 는
//   별 파일 WatchDetailRowComponents.swift 로 이동.

// MARK: - Note editor sheet — Round 22 (Hyemi): MeasurementNoteEditor 는 별 파일 MeasurementNoteEditor.swift 로 이동.

// Round (잔여 분할): QuartzBatteryCard 는 별 파일 QuartzBatteryCard.swift 로 이동.

#Preview {
    NavigationStack {
        WatchDetailView(watch: Watch(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602"))
    }
    .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
    .environment(UserPreferences())
}
