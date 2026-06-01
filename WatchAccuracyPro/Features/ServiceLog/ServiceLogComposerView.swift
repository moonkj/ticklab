import SwiftData
import SwiftUI

struct ServiceLogComposerView: View {
    let watch: Watch
    var existing: ServiceLog?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences

    @State private var type: ServiceType = .checkup
    @State private var date: Date = .init()
    @State private var center: String = ""
    @State private var costText: String = ""
    @State private var note: String = ""
    @State private var showingDiscardAlert = false
    @State private var showTextFilterAlert = false
    /// Sprint 3 (P2-11): 워치메이커 즐겨찾기 자동완성.
    @State private var showFavorites: Bool = false
    private var filteredFavorites: [String] {
        let all = ServiceCenterFavoritesService.all
        guard !center.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(center) }
    }

    private var isDirty: Bool {
        !center.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !costText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "service.section.type")) {
                    Picker(String(localized: "service.picker.type"), selection: $type) {
                        ForEach(ServiceType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                }
                Section(String(localized: "service.section.record")) {
                    DatePicker(String(localized: "service.date"), selection: $date, displayedComponents: .date)
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(String(localized: "service.center"), text: $center)
                            .onChange(of: center) { _, _ in showFavorites = true }
                        // Sprint 3 (P2-11): 즐겨찾기 자동완성 드롭다운.
                        if showFavorites && !filteredFavorites.isEmpty {
                            Divider().padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredFavorites, id: \.self) { fav in
                                        Button(fav) {
                                            center = fav
                                            showFavorites = false
                                        }
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AppColors.accent50)
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    TextField(String(localized: "service.cost"), text: $costText)
                        .keyboardType(.numberPad)
                }
                Section(String(localized: "service.section.note")) {
                    TextField(String(localized: "service.note.placeholder"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: existing == nil ? "service.title.add" : "service.title.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        if isDirty { showingDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
            .alert(String(localized: "common.discard.title"), isPresented: $showingDiscardAlert) {
                Button(String(localized: "common.discard.confirm"), role: .destructive) { dismiss() }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "common.discard.message"))
            }
            .alert(String(localized: "text.filter.blocked.title"), isPresented: $showTextFilterAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "text.filter.blocked.body")) }
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        type = existing.type
        date = existing.timestamp
        center = existing.serviceCenter
        if let cost = existing.costAmount {
            costText = "\(NSDecimalNumber(decimal: cost).intValue)"
        }
        note = existing.notes
    }

    private func save() {
        // 욕설 등 부적절 텍스트 사전 필터(자유 입력 필드만 — 비용/날짜/타입 제외).
        let userTexts = [center, note]
        if userTexts.contains(where: { CommunityTextModerator.containsProfanity($0) }) {
            showTextFilterAlert = true
            return
        }
        let log = existing ?? ServiceLog(watch: watch)
        log.type = type
        log.timestamp = date
        log.serviceCenter = center
        log.notes = note
        // Sprint 3 (P2-11): 저장 시 즐겨찾기에 추가 (LRU).
        if !center.trimmingCharacters(in: .whitespaces).isEmpty {
            ServiceCenterFavoritesService.recordUsage(center)
        }
        if let cost = Decimal(string: costText) {
            log.costAmount = cost
            log.costCurrency = "KRW"
        }
        // 다음 service 권장 일자 자동 계산.
        if let months = type.recommendedIntervalMonths {
            log.nextServiceDate = Calendar.current.date(byAdding: .month, value: months, to: date)
        }
        if existing == nil { modelContext.insert(log) }
        try? modelContext.save()
        // 사용자 요청: fullOverhaul ServiceLog 추가 시 해당 시계 오버홀 알림 재예약.
        if type == .fullOverhaul {
            NotificationService.scheduleOverhaulReminder(
                for: watch,
                lastOverhaulDate: date,
                years: preferences.overhaulReminderYears,
                enabled: preferences.overhaulReminderEnabled
            )
        }
        dismiss()
    }
}
