import StoreKit
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Watch.createdAt, order: .reverse) private var allWatches: [Watch]

    @State private var inputManager = AudioInputManager.shared
    // Round 138 (관리자 모드 — git commit 시 제외해야 할 영역 시작) {
    @State private var adminTapCount: Int = 0
    @State private var showingAdminPinPrompt: Bool = false
    @State private var adminPinInput: String = ""
    @State private var showingAdminPanel: Bool = false
    @State private var adminPinError: Bool = false
    // } Round 138 끝
    /// Round 175: 알림 권한 거부 안내 alert.
    @State private var showNotificationPermissionAlert: Bool = false
    /// Round 175: iCloud 토글 변경 시 재시작 안내.
    @State private var showRestartAlert: Bool = false
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// Pro 사용자가 hero 탭하면 StoreKit manage subscriptions 진입.
    @State private var showingManageSubscriptions: Bool = false

    /// CoreML 모델 가용성 → 현재 active detector. (Round 81: 인라인 한국어 → localize)
    private var coreMLStatus: String {
        let mlDetector = CoreMLBeatDetector()
        return mlDetector.isModelAvailable
            ? String(localized: "settings.coreml.status_coreml")
            : String(localized: "settings.coreml.status_rule")
    }

    /// Round 80: Apple Intelligence 가용성 — iOS 26 + 호환 디바이스 + 활성.
    private var aiAvailable: Bool {
        AppleIntelligenceVerdictService.shared.isAppleIntelligenceAvailable
    }

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            Form {
                // Round 48: Founder hero card (디자인 SSOT screens-main.jsx SettingsView).
                Section {
                    accountHero
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                // Round 133 사용자 요청: 사용자 모드 선택 메뉴 제거 — 항상 pro 모드 고정 (전문 분석).

                Section {
                    Toggle(String(localized: "settings.silent_mode_default"), isOn: $preferences.silentModeDefault)
                    // Round 133: 측정 중 항상 화면 켜기 — 기본 ON.
                    Toggle(String(localized: "settings.keep_screen_on"), isOn: $preferences.keepScreenOnDuringMeasurement)
                    audioInputPicker
                    // Round 138 사용자 요청: CoreML beat detector 토글 제거 — 일반 사용자에게 의미 없는 옵션.
                } header: {
                    Text(String(localized: "settings.section.measurement"))
                } footer: {
                    Text(String(localized: "settings.silent_mode_default.hint"))
                }

                // Round 138 사용자 요청: 동기화 섹션 (무브먼트 DB 자동 업데이트 / 지금 업데이트 확인) 제거.
                // 원자시계 시간 확인도 일반 사용자에게 의미 없어 제거 후보 — 사용자 확인 후 처리.

                // Round 80: Apple Intelligence 진단 토글 + 시스템 가용성 안내.
                Section {
                    Toggle(String(localized: "settings.ai.toggle"), isOn: $preferences.aiVerdictEnabled)
                    if preferences.aiVerdictEnabled && !aiAvailable {
                        Button {
                            // Round 97 (이형준 #9): App-Prefs: 는 iOS 14+ 차단됨 → openSettingsURLString.
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.warning)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "settings.ai.unavailable.title"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.ink0)
                                    Text(String(localized: "settings.ai.unavailable.body"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppColors.ink2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(String(localized: "settings.section.ai"))
                } footer: {
                    Text(preferences.aiVerdictEnabled
                         ? String(localized: "settings.ai.footer.on")
                         : String(localized: "settings.ai.footer.off"))
                }

                // Round 133 사용자 요청: '리마인드' 메뉴로 일기 알림 + 랜덤 시계 추천 통합.
                Section {
                    // 일기 알림 — Round 145 (Jay 4 P0): 권한 거부 시 토글 자동 revert.
                    Toggle(String(localized: "settings.journal_reminder"), isOn: Binding(
                        get: { preferences.journalReminderEnabled },
                        set: { newValue in
                            preferences.journalReminderEnabled = newValue
                            if newValue {
                                Task {
                                    let status = await NotificationService.authorizationStatus()
                                    if status == .denied {
                                        await MainActor.run {
                                            preferences.journalReminderEnabled = false
                                            showNotificationPermissionAlert = true
                                        }
                                    } else {
                                        NotificationService.scheduleJournalReminder(
                                            enabled: true,
                                            hour: preferences.journalReminderHour,
                                            minute: preferences.journalReminderMinute
                                        )
                                    }
                                }
                            } else {
                                NotificationService.scheduleJournalReminder(
                                    enabled: false,
                                    hour: preferences.journalReminderHour,
                                    minute: preferences.journalReminderMinute
                                )
                            }
                        }
                    ))
                    if preferences.journalReminderEnabled {
                        DatePicker(String(localized: "settings.journal_reminder.time"),
                                   selection: Binding(
                                    get: {
                                        Calendar.current.date(bySettingHour: preferences.journalReminderHour,
                                                              minute: preferences.journalReminderMinute,
                                                              second: 0, of: Date()) ?? Date()
                                    },
                                    set: { date in
                                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                        preferences.journalReminderHour = c.hour ?? 21
                                        preferences.journalReminderMinute = c.minute ?? 0
                                        NotificationService.scheduleJournalReminder(
                                            enabled: true,
                                            hour: preferences.journalReminderHour,
                                            minute: preferences.journalReminderMinute
                                        )
                                    }
                                   ),
                                   displayedComponents: .hourAndMinute
                        )
                    }
                    // 랜덤 시계 추천 — Round 145 (Jay 4 P0): 권한 거부 시 자동 revert.
                    Toggle(String(localized: "settings.random_pick.toggle"), isOn: Binding(
                        get: { preferences.randomPickEnabled },
                        set: { newValue in
                            preferences.randomPickEnabled = newValue
                            if newValue {
                                Task {
                                    let status = await NotificationService.authorizationStatus()
                                    if status == .denied {
                                        await MainActor.run {
                                            preferences.randomPickEnabled = false
                                            showNotificationPermissionAlert = true
                                        }
                                    } else {
                                        await MainActor.run { reschedulePick() }
                                    }
                                }
                            } else {
                                reschedulePick()
                            }
                        }
                    ))
                    if preferences.randomPickEnabled {
                        DatePicker(String(localized: "settings.random_pick.time"), selection: Binding(
                            get: {
                                Calendar.current.date(bySettingHour: preferences.randomPickHour,
                                                       minute: preferences.randomPickMinute,
                                                       second: 0,
                                                       of: Date()) ?? Date()
                            },
                            set: { newDate in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                preferences.randomPickHour = comps.hour ?? 8
                                preferences.randomPickMinute = comps.minute ?? 0
                                reschedulePick()
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                    // 사용자 요청: 오버홀 정비 리마인더 — 기본 ON, 주기 사용자 설정 (2~7년).
                    Toggle(String(localized: "settings.overhaul_reminder"), isOn: Binding(
                        get: { preferences.overhaulReminderEnabled },
                        set: { newValue in
                            preferences.overhaulReminderEnabled = newValue
                            rescheduleOverhaulReminders()
                        }
                    ))
                    if preferences.overhaulReminderEnabled {
                        Picker(String(localized: "settings.overhaul_reminder.years"),
                               selection: Binding(
                                get: { preferences.overhaulReminderYears },
                                set: { newValue in
                                    preferences.overhaulReminderYears = newValue
                                    rescheduleOverhaulReminders()
                                }
                               )) {
                            ForEach(2...7, id: \.self) { y in
                                Text(String(format: NSLocalizedString("settings.overhaul_reminder.years.value", comment: ""), y))
                                    .tag(y)
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "settings.section.reminders"))
                } footer: {
                    Text(String(localized: "settings.section.reminders.footer"))
                }
                Section(String(localized: "settings.section.security")) {
                    Toggle(String(localized: "settings.applock"), isOn: $preferences.appLockEnabled)
                    if preferences.appLockEnabled {
                        // Round 140 (Min H7/H8): PIN 토글 OFF 시 Keychain hash 도 함께 삭제 → 다시 켰을 때 옛 PIN 부활 방지.
                        Toggle(String(localized: "settings.applock.pin_enabled"), isOn: Binding(
                            get: { preferences.pinEnabled },
                            set: { newValue in
                                preferences.pinEnabled = newValue
                                if !newValue {
                                    PINService.shared.clearPIN()
                                }
                            }
                        ))
                        if preferences.pinEnabled {
                            NavigationLink(String(localized: "settings.applock.pin_setup")) {
                                PINSetupView()
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.warning)
                                Text(String(localized: "settings.applock.pin_warning"))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.ink2)
                            }
                        }
                    }
                    LabeledContent(String(localized: "settings.serial_mask")) {
                        Text(String(localized: "settings.serial_mask.value")).foregroundStyle(.tertiary)
                    }
                }
                // Round 134 사용자 요청: 자기장 측정 토글 제거 — 오늘 탭에서 항상 노출.
                Section(String(localized: "settings.section.help")) {
                    NavigationLink(String(localized: "settings.glossary"), destination: GlossaryView())
                }
                Section(String(localized: "settings.section.about")) {
                    // 사용자 요청: Bundle ID + Movement DB Version 제거. 버전 10번 클릭으로 관리자 모드 진입.
                    LabeledContent(
                        String(localized: "settings.version"),
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    )
                    .contentShape(Rectangle())
                    #if DEBUG
                    .onTapGesture {
                        // Round (하드코딩 audit): admin entry 자체를 #if DEBUG 로 묶음 — release 빌드에선
                        //   tap 이 admin prompt 띄우지 않으므로 "Admin Access"/"PIN" 등 영문 literal 도 사용자 미노출.
                        adminTapCount += 1
                        if adminTapCount >= 10 {
                            adminTapCount = 0
                            adminPinInput = ""
                            adminPinError = false
                            showingAdminPinPrompt = true
                        }
                    }
                    #endif
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            // Round 138 사용자 보고: 설정 화면 상단 제목 안 보임 → inline 고정으로 명확히.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.paper0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .onAppear { inputManager.refresh() }
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
            .alert(
                String(localized: "settings.icloud.restart.title"),
                isPresented: $showRestartAlert
            ) {
                Button(String(localized: "common.done"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.icloud.restart.body"))
            }
            // Round 138 (관리자 모드 — DEBUG 전용 영역) {
            #if DEBUG
            .alert("Admin Access", isPresented: $showingAdminPinPrompt) {
                SecureField("PIN", text: $adminPinInput)
                    .keyboardType(.numberPad)
                Button("Enter") {
                    if adminPinInput == "1639316" {
                        adminPinInput = ""
                        showingAdminPanel = true
                    } else {
                        adminPinError = true
                    }
                }
                Button("Cancel", role: .cancel) {
                    adminPinInput = ""
                }
            } message: {
                Text(adminPinError ? "Wrong PIN." : "Enter admin PIN.")
            }
            #endif
            // Round 149 (Hyemi 7 C3): sheet 자체도 #if DEBUG — release 빌드 안 컴파일.
            #if DEBUG
            .sheet(isPresented: $showingAdminPanel) {
                AdminPanelView()
                    .environment(preferences)
            }
            #endif
            // } Round 138 끝
        }
    }

    @ViewBuilder
    /// Round 48/78/97 — Founder hero card (디자인 SSOT screens-main.jsx SettingsView).
    /// primary-900 → primary-700 gradient bg, gold sparkle icon + glow, Founder badge.
    /// Round 97: tap 시 진동 피드백 (Phase 2 — Purchase 시트 진입).
    private var accountHero: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // 사용자 보고 fix: Pro 면 paywall 대신 StoreKit 구독 관리 sheet 열기 (이전엔 no-op UX dead end).
            if preferences.isPro {
                showingManageSubscriptions = true
            } else {
                purchaseRouter?.intend(.settings)
            }
        } label: {
            heroContent
        }
        .buttonStyle(.plain)
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
    }

    private var heroContent: some View {
        HStack(spacing: 14) {
            ZStack {
                // Gold glow halo.
                Circle()
                    .fill(AppColors.accent.opacity(0.6))
                    .frame(width: 70, height: 70)
                    .blur(radius: 14)
                LinearGradient(
                    colors: [AppColors.accent, AppColors.accentDark],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppColors.primaryDeep)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: preferences.isPro ? "settings.account.pro_name" : "settings.account.free_name"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: preferences.isPro ? "settings.account.pro_body" : "settings.account.free_body"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppColors.primaryDeep, AppColors.primary700],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // Round 148 (Doyoon 4 #3): modeRow dead — UserMode 토글 제거 후 호출처 없음. 제거.

    @ViewBuilder
    private var audioInputPicker: some View {
        // Round 162/175: 입력이 내장 마이크 하나뿐이면 picker 숨김 (혼란 방지).
        // 0개일 때만 empty message (이전 if/else 조건 dead branch 수정).
        if inputManager.available.count <= 1 {
            EmptyView()
        } else {
            Picker(String(localized: "settings.audio_input.label"),
                   selection: Binding(
                    get: { inputManager.preferredInputUID ?? "" },
                    set: { newValue in
                        if newValue.isEmpty {
                            inputManager.setPreferred(nil)
                        } else if let input = inputManager.available.first(where: { $0.id == newValue }) {
                            inputManager.setPreferred(input)
                        }
                    })
            ) {
                Text(String(localized: "settings.audio_input.system_default")).tag("")
                ForEach(inputManager.available) { input in
                    Text(input.displayName).tag(input.id)
                }
            }
        }
    }

    // Round 138 사용자 요청: 동기화 / 원자시계 섹션 제거되어 runOTA / runNTP 도 제거.

    private func reschedulePick() {
        NotificationService.scheduleRandomPick(
            watches: allWatches,
            hour: preferences.randomPickHour,
            minute: preferences.randomPickMinute,
            enabled: preferences.randomPickEnabled
        )
    }

    /// 사용자 요청: 오버홀 토글/주기 변경 시 모든 시계 재스케줄.
    private func rescheduleOverhaulReminders() {
        NotificationService.rescheduleAllOverhaulReminders(
            watches: allWatches,
            years: preferences.overhaulReminderYears,
            enabled: preferences.overhaulReminderEnabled,
            in: modelContext
        )
    }
}

struct GlossaryView: View {
    /// Round 85/101: 디자인 SSOT screens-detail.jsx GlossaryView — search field + card style entries.
    @State private var query: String = ""

    private let entries: [(key: String, descKey: String, icon: String)] = [
        ("glossary.bph", "glossary.bph.desc", "metronome"),
        ("glossary.rate", "glossary.rate.desc", "speedometer"),
        ("glossary.beat_error", "glossary.beat_error.desc", "waveform"),
        ("glossary.amplitude", "glossary.amplitude.desc", "wave.3.right"),
        ("glossary.cosc", "glossary.cosc.desc", "checkmark.seal"),
        ("glossary.lift_angle", "glossary.lift_angle.desc", "angle"),
        ("glossary.coaxial", "glossary.coaxial.desc", "gearshape.2"),
        ("glossary.mic", "glossary.mic.desc", "mic"),
        ("glossary.onsets", "glossary.onsets.desc", "dot.radiowaves.left.and.right"),
        // Round 121 (이형준 #11): 자주 나오는데 Glossary 에 없는 단어들.
        ("glossary.confidence", "glossary.confidence.desc", "chart.bar.fill"),
        ("glossary.snr", "glossary.snr.desc", "speaker.wave.3"),
        ("glossary.drift", "glossary.drift.desc", "arrow.left.and.right"),
        ("glossary.isochronism", "glossary.isochronism.desc", "clock.arrow.2.circlepath"),
        ("glossary.positional", "glossary.positional.desc", "rotate.3d"),
        // 사용자 요청: 자주 등장하지만 미수록 — power reserve / overhaul / magnetism / escapement.
        ("glossary.power_reserve", "glossary.power_reserve.desc", "battery.75"),
        ("glossary.overhaul", "glossary.overhaul.desc", "wrench.and.screwdriver"),
        ("glossary.magnetism", "glossary.magnetism.desc", "bolt.fill"),
        ("glossary.escapement", "glossary.escapement.desc", "gearshape"),
    ]

    private var filtered: [(key: String, descKey: String, icon: String)] {
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            let title = String(localized: String.LocalizationValue(entry.key)).lowercased()
            let desc = String(localized: String.LocalizationValue(entry.descKey)).lowercased()
            let q = query.lowercased()
            return title.contains(q) || desc.contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if filtered.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 32)
                }
                ForEach(filtered, id: \.key) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: String.LocalizationValue(entry.key)))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                            Text(String(localized: String.LocalizationValue(entry.descKey)))
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.paper1)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .searchable(text: $query, prompt: String(localized: "glossary.search.prompt"))
        .navigationTitle(String(localized: "glossary.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Round 138 (관리자 모드 — git commit 시 제외해야 할 영역 시작) {
// Round 149 (Hyemi 7 C3 Critical): AdminPanelView 전체를 #if DEBUG 로 감싸 release 빌드 컴파일 차단.
#if DEBUG
/// 관리자 패널 — 개발/QA 테스트 기능. App Store 빌드 전 제거 필수.
/// 사용자 요청: 데모 시계 10종 + 측정 20개씩 시드, wipe, preferences reset, cache invalidate.
private struct AdminPanelView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allWatches: [Watch]
    @Query private var allMeasurements: [WatchMeasurement]
    @Query private var allJournalEntries: [JournalEntry]
    @Query private var allServiceLogs: [ServiceLog]
    @Query private var allWearLogs: [WearLog]
    @Query private var allSpecCards: [SpecCard]

    @State private var seedToast: String? = nil
    @State private var showWipeConfirm = false
    @State private var showResetPrefsConfirm = false

    var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            Form {
                Section("License Mode") {
                    Toggle("Pro Unlocked", isOn: Binding(
                        get: { prefs.isPro },
                        set: { newValue in
                            prefs.isPro = newValue
                            ProEntitlement.shared.markPro(newValue)
                        }
                    ))
                    Text(prefs.isPro
                         ? "Pro: 무제한 시계, 모든 기능 사용 가능"
                         : "Free: 시계 최대 \(ProEntitlement.freeWatchLimit)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Status") {
                    LabeledContent("Watches", value: "\(allWatches.count)")
                    LabeledContent("Measurements", value: "\(allMeasurements.count)")
                    LabeledContent("Journals", value: "\(allJournalEntries.count)")
                    LabeledContent("Service logs", value: "\(allServiceLogs.count)")
                    LabeledContent("Wear logs", value: "\(allWearLogs.count)")
                    LabeledContent("Spec cards", value: "\(allSpecCards.count)")
                }
                Section("Seed Demo Data") {
                    Button {
                        let added = seedDemoWatches(in: modelContext)
                        seedToast = "✅ \(added) 시계 + 측정 데이터 시드 완료"
                    } label: {
                        Label("Seed 10 watches + 20 measurements each", systemImage: "sparkles")
                    }
                    Button {
                        let counts = seedJournalServiceWearSpecCard(watches: allWatches, in: modelContext)
                        seedToast = "✅ 일기 \(counts.0) / 서비스 \(counts.1) / 착용 \(counts.2) / 스펙 \(counts.3) 시드 완료"
                    } label: {
                        Label("Seed journal/service/wear/spec for existing watches", systemImage: "doc.text.fill")
                    }
                    .disabled(allWatches.isEmpty)
                    if let toast = seedToast {
                        Text(toast)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Section("Wipe Data") {
                    Button(role: .destructive) {
                        showWipeConfirm = true
                    } label: {
                        Label("Wipe ALL data (watches/measurements/journals/...)", systemImage: "trash.fill")
                    }
                    .confirmationDialog("모든 데이터 삭제할까요?", isPresented: $showWipeConfirm) {
                        Button("전부 삭제", role: .destructive) {
                            wipeAllData(in: modelContext, watches: allWatches)
                            seedToast = "🗑️ 모든 데이터 삭제 완료"
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("시계 + 측정 + 일기 + 서비스 로그 + 착용 기록 + 스펙 카드 모두 삭제됩니다.")
                    }
                }
                Section("Preferences Reset") {
                    Button(role: .destructive) {
                        showResetPrefsConfirm = true
                    } label: {
                        Label("Reset all UserDefaults flags", systemImage: "arrow.counterclockwise.circle")
                    }
                    .confirmationDialog("모든 환경설정 초기화", isPresented: $showResetPrefsConfirm) {
                        Button("초기화", role: .destructive) {
                            resetAllPreferences(prefs: prefs, watches: allWatches)
                            seedToast = "🔄 환경설정 초기화 (onboarding/winding hint/알림/PIN 등)"
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("Pro mode 토글은 유지되며, 나머지 flag 가 default 로 reset 됩니다.")
                    }
                }
                Section("Caches") {
                    Button {
                        WatchMoodService.invalidateAll()
                        for w in allWatches { PhotoCache.invalidate(id: w.id) }
                        seedToast = "🧹 Cache 비움 (WatchMood + PhotoCache)"
                    } label: {
                        Label("Invalidate WatchMood + PhotoCache", systemImage: "memorychip")
                    }
                }
                Section("Debug Reset") {
                    Button("Reset onboarding", role: .destructive) {
                        dismiss()
                        prefs.hasCompletedOnboarding = false
                    }
                    Button("Clear PIN", role: .destructive) {
                        prefs.pinEnabled = false
                        PINService.shared.clearPIN()
                    }
                    Button("Reset winding hint") {
                        UserDefaults.standard.removeObject(forKey: "ticklab.windingHintShownAt")
                        seedToast = "✅ 와인딩 안내 토스트 한 번 더 표시"
                    }
                }
            }
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Seed: 데모 시계 10종 + 측정 데이터

    /// 다양한 brand/caliber/movementType 의 데모 시계 10종 시드. 각 시계에 측정 20개.
    @discardableResult
    private func seedDemoWatches(in context: ModelContext) -> Int {
        struct Spec {
            let brand: String, model: String, caliber: String?, type: WatchMovementType, bphFallback: Int
        }
        let specs: [Spec] = [
            .init(brand: "Rolex", model: "Submariner", caliber: "Rolex_3135", type: .automatic, bphFallback: 28800),
            .init(brand: "Omega", model: "Seamaster", caliber: "Omega_8800", type: .automatic, bphFallback: 25200),
            .init(brand: "IWC", model: "Portugieser", caliber: "IWC_82110", type: .automatic, bphFallback: 28800),
            .init(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602", type: .automatic, bphFallback: 28800),
            .init(brand: "Seiko", model: "SARB033", caliber: "Seiko_6R15", type: .automatic, bphFallback: 21600),
            .init(brand: "Hamilton", model: "Khaki Field", caliber: "Hamilton_H10", type: .automatic, bphFallback: 21600),
            .init(brand: "Breguet", model: "Classique", caliber: "Breguet_Cal502", type: .automatic, bphFallback: 21600),
            .init(brand: "Patek Philippe", model: "Calatrava", caliber: "ETA_2824", type: .manual, bphFallback: 28800),
            .init(brand: "Citizen", model: "Eco-Drive", caliber: nil, type: .quartz, bphFallback: 0),
            .init(brand: "Casio", model: "G-Shock", caliber: nil, type: .quartz, bphFallback: 0)
        ]
        let now = Date()
        var inserted = 0
        for (idx, s) in specs.enumerated() {
            let nominal = s.bphFallback
            let watch = Watch(
                brand: s.brand,
                model: s.model,
                caliber: s.caliber,
                purchaseDate: now.addingTimeInterval(-86400 * Double((idx + 1) * 120)),
                isFavorite: idx % 3 == 0,
                isPrimary: idx == 0,
                movementType: s.type,
                createdAt: now.addingTimeInterval(-86400 * Double(60 - idx * 4))
            )
            context.insert(watch)
            // quartz 는 측정 불가 — measurement 시드 skip.
            guard nominal > 0 else {
                inserted += 1
                continue
            }
            for m in 0..<20 {
                // rate 분포: -8 ~ +8 s/d 안에 다양. 일부 outlier ±15.
                let rate: Double = {
                    let base = Double(m % 5) - 2.0  // -2..+2
                    let drift = Double.random(in: -2.5...2.5)
                    return base + drift
                }()
                let beatErr: Double = Double.random(in: 0.1...0.8)
                let amplitude: Double = Double.random(in: 260...295)
                let confidence: Int = Int.random(in: 75...96)
                let daysAgo: Double = Double(m) * 1.6 + Double.random(in: 0...0.4)
                let measurement = WatchMeasurement(
                    watch: watch,
                    timestamp: now.addingTimeInterval(-86400 * daysAgo),
                    rateSecondsPerDay: rate,
                    beatErrorMs: beatErr,
                    amplitudeDegrees: amplitude,
                    bph: nominal,
                    confidenceScore: confidence,
                    durationSeconds: 30
                )
                context.insert(measurement)
            }
            inserted += 1
        }
        try? context.save()
        return inserted
    }

    // MARK: - Seed: Journal/Service/Wear/SpecCard (기존 시계 대상)

    private func seedJournalServiceWearSpecCard(watches: [Watch], in context: ModelContext) -> (Int, Int, Int, Int) {
        let moods: [Mood] = [.happy, .proud, .neutral, .curious, .nostalgic]
        let bodies = [
            "오늘은 이 시계 차고 외출.",
            "오버홀 끝나고 첫 측정.",
            "갈색 스트랩 교체 — 분위기 완전 다름.",
            "가족 식사. 격식 있는 자리.",
            "운동 후 컨디션 체크."
        ]
        let now = Date()
        var jCount = 0, sCount = 0, wCount = 0, scCount = 0
        for (idx, w) in watches.enumerated() {
            // Journal 5개
            for j in 0..<5 {
                let entry = JournalEntry(
                    watch: w,
                    timestamp: now.addingTimeInterval(-86400 * Double(j * 6 + idx)),
                    body: bodies[j % bodies.count],
                    mood: moods[j % moods.count]
                )
                context.insert(entry)
                jCount += 1
            }
            // ServiceLog 2개
            for (k, sType) in [ServiceType.fullOverhaul, ServiceType.checkup].enumerated() {
                let log = ServiceLog(watch: w)
                log.type = sType
                log.timestamp = now.addingTimeInterval(-86400 * Double(k == 0 ? 365 * 5 : 365))
                log.serviceCenter = sType == .fullOverhaul ? "공식 서비스센터" : "지정 워치메이커"
                log.notes = sType == .fullOverhaul ? "5년 풀 오버홀, 가스켓 교체" : "정기 점검"
                if let months = sType.recommendedIntervalMonths {
                    log.nextServiceDate = Calendar.current.date(byAdding: .month, value: months, to: log.timestamp)
                }
                context.insert(log)
                sCount += 1
            }
            // WearLog 지난 30일 중 18일 (60%)
            for d in 0..<30 where d % 5 != 0 {
                let date = Calendar.current.startOfDay(for: now.addingTimeInterval(-86400 * Double(d)))
                let log = WearLog(watch: w, date: date, isAuto: Bool.random())
                context.insert(log)
                wCount += 1
            }
            // SpecCard 1개
            let card = SpecCard(watch: w)
            context.insert(card)
            scCount += 1
        }
        try? context.save()
        return (jCount, sCount, wCount, scCount)
    }

    // MARK: - Wipe

    private func wipeAllData(in context: ModelContext, watches: [Watch]) {
        for w in watches {
            w.deleteCascade(in: context)
        }
        // Orphan 정리 — cascade 안 잡힌 경우 (예: watch 없는 journal/log/wear).
        (try? context.fetch(FetchDescriptor<JournalEntry>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<ServiceLog>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<WearLog>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<SpecCard>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<WatchMeasurement>()))?.forEach { context.delete($0) }
        try? context.save()
        WatchMoodService.invalidateAll()
    }

    // MARK: - Preferences reset

    private func resetAllPreferences(prefs: UserPreferences, watches: [Watch]) {
        prefs.hasCompletedOnboarding = false
        prefs.silentModeDefault = false
        prefs.aiVerdictEnabled = true
        prefs.keepScreenOnDuringMeasurement = true
        prefs.journalReminderEnabled = false
        prefs.randomPickEnabled = false
        prefs.useSimplifiedDSP = true
        prefs.magneticFieldMeasurementEnabled = false
        prefs.appLockEnabled = false
        prefs.pinEnabled = false
        prefs.autoUpdateMovementDB = false
        UserDefaults.standard.removeObject(forKey: "ticklab.windingHintShownAt")
        UserDefaults.standard.removeObject(forKey: "ticklab.fallbackAcknowledged")
        UserDefaults.standard.removeObject(forKey: "ticklab.lastLaunchUsedInMemoryFallback")
        NotificationService.cancelJournalReminder()
        NotificationService.cancelRandomPick()
        for w in watches {
            NotificationService.cancelWindReminder(for: w)
            NotificationService.cancelBatteryReminder(for: w)
        }
        PINService.shared.clearPIN()
    }
}

#endif
// } Round 138 끝 / Round 149 (Hyemi 7 C3) — AdminPanel #if DEBUG 가드

#Preview {
    SettingsView()
        .environment(UserPreferences())
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
