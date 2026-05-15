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
                    HStack {
                        Text(String(localized: "settings.serial_mask"))
                        Spacer()
                        Text(String(localized: "settings.serial_mask.value")).foregroundStyle(.tertiary)
                    }
                }
                // Round 134 사용자 요청: 자기장 측정 토글 제거 — 오늘 탭에서 항상 노출.
                Section(String(localized: "settings.section.help")) {
                    NavigationLink(String(localized: "settings.glossary"), destination: GlossaryView())
                }
                Section(String(localized: "settings.section.about")) {
                    LabeledContent(String(localized: "settings.version"), value: "0.2.0")
                    LabeledContent(String(localized: "settings.bundle_id"), value: "com.ticklab.watchaccuracypro")
                    // Round 138 (관리자 모드 — 10번 연속 클릭 → PIN prompt). git commit 시 제외할 영역.
                    LabeledContent(
                        String(localized: "settings.movementdb.version"),
                        value: MovementDBOTAService.shared.installedVersion() ?? "bundled"
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        adminTapCount += 1
                        if adminTapCount >= 10 {
                            adminTapCount = 0
                            adminPinInput = ""
                            adminPinError = false
                            showingAdminPinPrompt = true
                        }
                    }
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
            // Round 138 (관리자 모드 — git commit 시 제외해야 할 영역 시작) {
            .alert("Admin Access", isPresented: $showingAdminPinPrompt) {
                SecureField("PIN", text: $adminPinInput)
                    .keyboardType(.numberPad)
                Button("Enter") {
                    // Round 148 (Jay 5 #6 Critical): #if DEBUG 가드 — release/AppStore 빌드 에서 admin 모드 차단.
                    // Note: literal — git commit 시 이 부분 제외.
                    #if DEBUG
                    if adminPinInput == "1639316" {
                        adminPinInput = ""
                        showingAdminPanel = true
                    } else {
                        adminPinError = true
                    }
                    #else
                    adminPinError = true  // Release 빌드: PIN 일치 여부 무관하게 진입 차단.
                    #endif
                }
                Button("Cancel", role: .cancel) {
                    adminPinInput = ""
                }
            } message: {
                Text(adminPinError ? "Wrong PIN." : "Enter admin PIN.")
            }
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
            // Phase 2: PurchaseView 시트 진입.
        } label: {
            heroContent
        }
        .buttonStyle(.plain)
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
}

extension ExportPayload {
    /// ShareLink 가 file URL 을 선호하므로 임시 디렉토리에 한 번 쓰고 URL 반환.
    var tempURL: URL? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            return nil
        }
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
/// 관리자 패널 — Free/Pro 모드 직접 전환. 개발용. App Store 빌드 전 제거 필수.
private struct AdminPanelView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            Form {
                Section("License Mode") {
                    // Round 147 (Min H1): ProEntitlement.markPro 호출로 @Published isPro 도 동기화.
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
                    LabeledContent("Watch limit", value: prefs.isPro ? "∞" : "\(ProEntitlement.freeWatchLimit)")
                    LabeledContent("Journal/month", value: prefs.isPro ? "∞" : "\(ProEntitlement.freeJournalMonthLimit)")
                    LabeledContent("AI trial/watch", value: prefs.isPro ? "∞" : "\(ProEntitlement.freeAITrialPerWatch)")
                }
                Section("Debug Reset") {
                    Button("Reset onboarding", role: .destructive) {
                        // Round 141 (Min H10): 진행 중 LongTest 세션도 정리 — onboarding 위로 timer fire 방지.
                        dismiss()
                        prefs.hasCompletedOnboarding = false
                    }
                    Button("Clear PIN", role: .destructive) {
                        prefs.pinEnabled = false
                        PINService.shared.clearPIN()
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
}
#endif
// } Round 138 끝 / Round 149 (Hyemi 7 C3) — AdminPanel #if DEBUG 가드

#Preview {
    SettingsView()
        .environment(UserPreferences())
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
