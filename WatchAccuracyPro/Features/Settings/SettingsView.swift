import StoreKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// Pro 사용자가 hero 탭하면 StoreKit manage subscriptions 진입.
    @State private var showingManageSubscriptions: Bool = false
    /// Sprint 2 (P1-7): manage subscription 직전 retention sheet.
    @State private var showingOffboarding: Bool = false
    /// Sprint 6 (P3-14): 인앱 피드백.
    @State private var showingFeedback: Bool = false
    /// #10 백업/복원: 로컬 JSON 가져오기.
    @State private var showingRestoreImporter: Bool = false
    @State private var restoreResult: Int? = nil
    /// R6: 컬렉션 자랑 카드(이미지) 공유.
    @State private var shareCardItem: ShareCardItem? = nil
    /// 기능 B: 공유카드 → 커뮤니티 직접 게시 흐름(크롭 → 캡션 리뷰 → 업로드).
    @State private var communityCardCrop: CropImagePayload?
    @State private var communityCardReview: PendingPost?
    @State private var communityCardPendingImage: UIImage?
    @State private var showCommunityCardEULA = false
    @State private var communityCardError: String?
    /// Sprint 10 (P3-13): 사용자 프로필
    @State private var showingProfile: Bool = false

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

    /// 프로필 요약 한 줄 — "2018년부터 · Rolex, Omega". 채워진 항목만 결합, 없으면 nil(기본 힌트 표시).
    private var profileSummaryLine: String? {
        var parts: [String] = []
        if !UserProfile.startYear.isEmpty {
            parts.append(String(format: String(localized: "profile.since"), UserProfile.startYear))
        }
        let brands = UserProfile.favoriteBrands.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brands.isEmpty { parts.append(brands) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            Form {
                // Sprint 11 (사용자 요청): 내 프로필을 별도 행으로 분리 — 구독 hero에 숨지 않게.
                Section {
                    Button { showingProfile = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                if let data = UserProfile.photoData, let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 48, height: 48).clipShape(Circle())
                                } else {
                                    Circle().fill(AppColors.paper2).frame(width: 48, height: 48)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 20)).foregroundStyle(AppColors.ink3)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    let name = UserProfile.displayName
                                    Text(name.isEmpty ? String(localized: "profile.nav.title") : name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.ink0)
                                    if UserProfile.isDealer {
                                        Text("DEALER")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(AppColors.primaryDeep)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(AppColors.accent).clipShape(Capsule())
                                    }
                                }
                                if let summary = profileSummaryLine {
                                    Text(summary)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.ink2)
                                        .lineLimit(1)
                                } else {
                                    Text(String(localized: UserProfile.displayName.isEmpty
                                                 ? "settings.profile.setup_hint" : "settings.profile.edit_hint"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.ink2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14)).foregroundStyle(AppColors.ink3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingProfile) { UserProfileView() }
                }
                // Round 48: Founder hero card (구독) — 프로필과 분리됨.
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
                    // T-17: 햅틱 피드백 전역 토글.
                    Toggle(String(localized: "settings.haptics"), isOn: $preferences.hapticsEnabled)
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
                            ForEach(2...10, id: \.self) { y in
                                Text(String(format: NSLocalizedString("settings.overhaul_reminder.years.value", comment: ""), y))
                                    .tag(y)
                            }
                        }
                    }
                    // Sprint 7 (P2-14): 로테이션 넛지
                    Toggle(String(localized: "settings.rotation_nudge"), isOn: Binding(
                        get: { preferences.rotationNudgeEnabled },
                        set: { preferences.rotationNudgeEnabled = $0 }
                    ))
                    if preferences.rotationNudgeEnabled {
                        Picker(String(localized: "settings.rotation_nudge.days"),
                               selection: Binding(
                                get: { preferences.rotationNudgeDays },
                                set: { preferences.rotationNudgeDays = $0 }
                               )) {
                            ForEach([3, 5, 7, 14, 30], id: \.self) { d in
                                Text(String(format: NSLocalizedString("settings.rotation_nudge.days.value", comment: ""), d)).tag(d)
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "settings.section.reminders"))
                } footer: {
                    Text(String(localized: "settings.section.reminders.footer"))
                }
                // Apple guideline 5.1.1/5.1.2 fix: Brand League 데이터 전송 옵트인 명시.
                Section {
                    Toggle(String(localized: "settings.brandleague.optin"),
                           isOn: $preferences.brandLeagueOptIn)
                } header: {
                    Text(String(localized: "settings.section.privacy"))
                } footer: {
                    Text(String(localized: "settings.brandleague.optin.footer"))
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
                Section {
                    Picker(String(localized: "settings.photo.quality"),
                           selection: Binding(
                            get: { PhotoQuality.current.rawValue },
                            set: { UserDefaults.standard.set($0, forKey: "ticklab.photoQuality") }
                           )) {
                        Text(String(localized: "settings.photo.quality.standard"))
                            .tag(PhotoQuality.standard.rawValue)
                        Text(String(localized: "settings.photo.quality.high"))
                            .tag(PhotoQuality.high.rawValue)
                        Text(String(localized: "settings.photo.quality.original"))
                            .tag(PhotoQuality.original.rawValue)
                    }
                    Text(String(localized: "settings.photo.quality.hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink3)
                } header: {
                    Text(String(localized: "settings.section.photo"))
                }

                Section {
                    let csvPayload = DataExportService.export(watches: allWatches, format: .csv)
                    if let url = csvPayload.tempURL {
                        ShareLink(item: url) {
                            HStack {
                                Image(systemName: "tablecells")
                                    .frame(width: 24)
                                Text(String(localized: "settings.data.export.csv"))
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.ink3)
                            }
                        }
                    }
                    let jsonPayload = DataExportService.export(watches: allWatches, format: .json)
                    if let url = jsonPayload.tempURL {
                        ShareLink(item: url) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .frame(width: 24)
                                Text(String(localized: "settings.data.export.json"))
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.ink3)
                            }
                        }
                    }
                    // #10 백업/복원: 로컬 JSON 파일에서 복원(가져오기). 외부 전송 0 (Hard Rule #8).
                    Button {
                        showingRestoreImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 24)
                            Text(String(localized: "settings.data.restore"))
                            Spacer()
                        }
                        .foregroundStyle(AppColors.ink0)
                    }
                    .fileImporter(isPresented: $showingRestoreImporter,
                                  allowedContentTypes: [.json]) { result in
                        handleRestore(result)
                    }
                    .alert(String(localized: "settings.data.restore.done"), isPresented: Binding(
                        get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } }
                    )) {
                        Button(String(localized: "common.ok"), role: .cancel) { restoreResult = nil }
                    } message: {
                        Text(String(format: String(localized: "settings.data.restore.result"), restoreResult ?? 0))
                    }
                    // Sprint 10 (P2-16): 공개 갤러리 HTML
                    if let galleryURL = CollectionGalleryGenerator.generate(
                        watches: allWatches, includePrices: false, ownerName: UserProfile.displayName
                    ) {
                        ShareLink(item: galleryURL) {
                            HStack {
                                Image(systemName: "globe").frame(width: 24)
                                Text(String(localized: "settings.data.gallery_html"))
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13)).foregroundStyle(AppColors.ink3)
                            }
                        }
                    }
                    // R6 비측정 바이럴: 컬렉션 자랑 카드(이미지) — 탭 시 생성 후 공유시트(인스타 등).
                    Button {
                        shareCardItem = CollectionShareCardGenerator.generate(
                            watches: allWatches, ownerName: UserProfile.displayName
                        ).map { ShareCardItem(url: $0) }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled").frame(width: 24)
                            Text(String(localized: "collection.sharecard.entry"))
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13)).foregroundStyle(AppColors.ink3)
                        }
                        .foregroundStyle(AppColors.ink0)
                    }
                    .sheet(item: $shareCardItem) { item in
                        ActivityShareSheet(items: [item.url])
                    }
                    // 기능 B: 공유카드를 커뮤니티에 바로 게시 (커뮤니티 활성 시에만 노출).
                    if FeatureFlags.shared.communityEnabled {
                        Button {
                            startCommunityCardPost()
                        } label: {
                            HStack {
                                Image(systemName: "person.2.fill").frame(width: 24)
                                Text(String(localized: "share.post_to_community"))
                                Spacer()
                                Image(systemName: "paperplane")
                                    .font(.system(size: 13)).foregroundStyle(AppColors.ink3)
                            }
                            .foregroundStyle(AppColors.ink0)
                        }
                        .fullScreenCover(item: $communityCardCrop) { payload in
                            PhotoCropView(
                                image: payload.image, aspect: 1.0,
                                onComplete: { data in communityCardCrop = nil; handleCommunityCardCropped(data) },
                                onCancel: { communityCardCrop = nil }
                            )
                        }
                        .fullScreenCover(item: $communityCardReview) { pending in
                            CommunityReviewView(
                                imageData: pending.data,
                                onPost: { caption in communityCardReview = nil; uploadCommunityCard(data: pending.data, caption: caption) },
                                onCancel: { communityCardReview = nil }
                            )
                        }
                        .sheet(isPresented: $showCommunityCardEULA) {
                            CommunityEULAView {
                                CommunityService.shared.acceptEULA()
                                if let img = communityCardPendingImage {
                                    communityCardPendingImage = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        communityCardCrop = CropImagePayload(image: img)
                                    }
                                }
                            }
                        }
                        .alert(String(localized: "community.upload.error"), isPresented: Binding(
                            get: { communityCardError != nil }, set: { if !$0 { communityCardError = nil } }
                        )) {
                            Button(String(localized: "common.ok"), role: .cancel) { communityCardError = nil }
                        } message: { Text(communityCardError ?? "") }
                    }
                    // Sprint 6 (P2-7): 컬렉션 마스터 리포트 PDF
                    let masterData = MasterReportGenerator.generate(watches: allWatches, includePrices: true)
                    let masterURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("TickLab_Collection_Report.pdf")
                    if (try? masterData.write(to: masterURL)) != nil {
                        ShareLink(item: masterURL) {
                            HStack {
                                Image(systemName: "doc.richtext.fill").frame(width: 24)
                                Text(String(localized: "settings.data.master_pdf"))
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13)).foregroundStyle(AppColors.ink3)
                            }
                        }
                    }
                    Text(String(localized: "settings.data.export.hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink3)
                } header: {
                    Text(String(localized: "settings.section.data"))
                }

                // Sprint 6 (P2-20): 친구 초대 레퍼럴
                Section {
                    NavigationLink { ReferralView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill").foregroundStyle(AppColors.accentDark)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.referral.title"))
                                    .font(.system(size: 15, weight: .semibold))
                                Text(String(localized: "settings.referral.subtitle"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.ink2)
                            }
                        }
                    }
                }

                Section(String(localized: "settings.section.help")) {
                    NavigationLink(String(localized: "settings.glossary"), destination: GlossaryView())
                    // 사용자 요청: 개인정보처리방침 · 이용약관 · 지원 in-app 접근. App Store 심사 권장.
                    Link(destination: URL(string: "https://moonkj.github.io/ticklab/support.html")!) {
                        HStack {
                            Text(String(localized: "settings.help.support"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    Link(destination: URL(string: "https://moonkj.github.io/ticklab/privacy.html")!) {
                        HStack {
                            Text(String(localized: "settings.help.privacy"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    Link(destination: URL(string: "https://moonkj.github.io/ticklab/terms.html")!) {
                        HStack {
                            Text(String(localized: "settings.help.terms"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    Link(destination: URL(string: "mailto:imurmkj@naver.com?subject=TickLab%20%EB%AC%B8%EC%9D%98")!) {
                        HStack {
                            Text(String(localized: "settings.help.contact"))
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    // Sprint 6 (P3-14): 인앱 피드백
                    Button {
                        showingFeedback = true
                    } label: {
                        HStack {
                            Text(String(localized: "settings.help.feedback"))
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    .sheet(isPresented: $showingFeedback) { InAppFeedbackView() }
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
            // Round 138 (관리자 모드 — DEBUG 전용 영역) {
            #if DEBUG
            .alert("관리자 접근", isPresented: $showingAdminPinPrompt) {
                SecureField("PIN", text: $adminPinInput)
                    .keyboardType(.numberPad)
                Button("입력") {
                    if adminPinInput == "1639316" {
                        adminPinInput = ""
                        showingAdminPanel = true
                    } else {
                        adminPinError = true
                    }
                }
                Button("취소", role: .cancel) {
                    adminPinInput = ""
                }
            } message: {
                Text(adminPinError ? "PIN이 틀렸습니다." : "관리자 PIN을 입력하세요.")
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
            // Sprint 2 (P1-7): Pro 면 offboarding retention sheet 먼저 — 사용자가 manage 선택 시에만 진입.
            if preferences.isPro {
                showingOffboarding = true
            } else {
                purchaseRouter?.intend(.settings)
            }
        } label: {
            heroContent
        }
        .buttonStyle(.plain)
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .sheet(isPresented: $showingOffboarding) {
            SubscriptionOffboardingView {
                showingManageSubscriptions = true
            }
        }
    }

    private var heroContent: some View {
        HStack(spacing: 14) {
            // 구독 hero — 프로필과 분리 (Sprint 11). 항상 sparkles 아이콘.
            ZStack {
                Circle().fill(AppColors.accent.opacity(0.6)).frame(width: 70, height: 70).blur(radius: 14)
                LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 56, height: 56).clipShape(Circle())
                Image(systemName: "sparkles").font(.system(size: 26, weight: .medium))
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
            LinearGradient(colors: [AppColors.primaryDeep, AppColors.primary700],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
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

    /// #10 백업/복원: 보안 스코프 URL 에서 JSON 읽어 복원. 결과 수를 alert 로.
    private func handleRestore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { restoreResult = 0; return }
        restoreResult = DataExportService.importWatches(from: data, into: modelContext)
    }

    // MARK: - 기능 B: 공유카드 → 커뮤니티 게시

    /// 컬렉션 공유카드를 생성해 EULA → 1:1 크롭 → 캡션 리뷰 → 업로드 흐름으로 진입.
    private func startCommunityCardPost() {
        guard CommunityService.shared.canPostToday else {
            communityCardError = String(localized: "community.daily_limit.body"); return
        }
        guard let url = CollectionShareCardGenerator.generate(watches: allWatches, ownerName: UserProfile.displayName),
              let img = UIImage(contentsOfFile: url.path) else {
            communityCardError = String(localized: "community.upload.error"); return
        }
        if CommunityService.shared.hasAcceptedEULA {
            communityCardCrop = CropImagePayload(image: img)
        } else {
            communityCardPendingImage = img
            showCommunityCardEULA = true
        }
    }

    private func handleCommunityCardCropped(_ data: Data) {
        // EXIF strip 강제(Hard Rule #8). 공유카드는 앱 생성물이라 민감콘텐츠 검열은 생략.
        let clean = EXIFStripper.strippedJPEG(from: data) ?? data
        communityCardReview = PendingPost(data: clean)
    }

    private func uploadCommunityCard(data: Data, caption: String) {
        Task {
            do {
                try await CommunityService.shared.uploadPost(imageData: data, brand: nil, caption: caption)
            } catch CommunityService.UploadError.dailyLimit {
                communityCardError = String(localized: "community.daily_limit.body")
            } catch {
                communityCardError = error.localizedDescription
            }
        }
    }

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

    @State private var selectedEntry: (key: String, descKey: String, icon: String)?

    var body: some View {
        ScrollView {
            // Sprint 8 (UX): 2열 그리드로 컴팩트하게 표시 — 탭 시 바텀 시트 상세
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if filtered.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .gridCellColumns(2)
                        .padding(.top, 32)
                }
                ForEach(filtered, id: \.key) { entry in
                    Button {
                        selectedEntry = entry
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(AppColors.accent)
                            Text(String(localized: String.LocalizationValue(entry.key)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(String(localized: String.LocalizationValue(entry.descKey)))
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.ink2)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(AppColors.paper1)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .searchable(text: $query, prompt: String(localized: "glossary.search.prompt"))
        .navigationTitle(String(localized: "glossary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { selectedEntry.map { GlossaryEntryID(key: $0.key, descKey: $0.descKey, icon: $0.icon) } },
            set: { if $0 == nil { selectedEntry = nil } }
        )) { item in
            GlossaryDetailSheet(key: item.key, descKey: item.descKey, icon: item.icon)
        }
    }
}

struct GlossaryEntryID: Identifiable {
    let id = UUID()
    let key: String; let descKey: String; let icon: String
}

struct GlossaryDetailSheet: View {
    let key: String; let descKey: String; let icon: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(AppColors.rule).frame(width: 36, height: 4).padding(.top, 10)
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(AppColors.accentDark)
            Text(String(localized: String.LocalizationValue(key)))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: String.LocalizationValue(descKey)))
                .font(.system(size: 15))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .background(AppColors.paper0.ignoresSafeArea())
    }
}

// Round 138 (관리자 모드 — git commit 시 제외해야 할 영역 시작) {
// Round 149 (Hyemi 7 C3 Critical): AdminPanelView 전체를 #if DEBUG 로 감싸 release 빌드 컴파일 차단.
#if DEBUG
/// 관리자 패널 — 개발/QA 테스트 기능. App Store 빌드 전 제거 필수.
/// 사용자 요청: 데모 시계 10종 + 측정 20개씩 시드, wipe, preferences reset, cache invalidate.
/// 관리자 운영 대시보드 — 신고 목록·숨김 + 통계(전체/오늘 게시물·현재 활동 사용자).
/// 신고 조회·활동 사용자·숨김은 admin RLS 필요(docs/community/admin_ops.sql). 게시물 수는 공개 읽기로 동작.
private struct AdminOpsView: View {
    private let service = CommunityService.shared
    @State private var stats = Community.OpsStats()
    @State private var reports: [Community.AdminReport] = []
    @State private var reportedPosts: [String: Community.Post] = [:]
    @State private var loaded = false
    @State private var composingAnnouncement = false
    @State private var announcements: [Community.Announcement] = []
    @State private var composingChannel = false
    @State private var channels: [Community.CuratedChannel] = []
    @State private var suggestions: [Community.ChannelSuggestion] = []

    private struct ReportGroup: Identifiable {
        let postID: String
        let count: Int
        let reasons: [String]
        var id: String { postID }
    }
    private var grouped: [ReportGroup] {
        Dictionary(grouping: reports, by: { $0.postID }).map { pid, items in
            ReportGroup(postID: pid, count: items.count,
                        reasons: Array(Set(items.map { reasonLabel($0.reason) })).sorted())
        }.sorted { $0.count > $1.count }
    }
    private func reasonLabel(_ raw: String) -> String {
        if let r = Community.ReportReason(rawValue: raw) {
            return String(localized: String.LocalizationValue(r.localizationKey))
        }
        return raw
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    AdminStatTile(icon: "person.2.fill", value: stats.activeUsers, label: "현재 활동", tone: AppColors.accent)
                    AdminStatTile(icon: "calendar", value: stats.todayPosts, label: "오늘 게시물", tone: AppColors.info)
                    AdminStatTile(icon: "square.grid.2x2", value: stats.totalPosts, label: "전체 게시물", tone: AppColors.ink2)
                    AdminStatTile(icon: "flag.fill", value: grouped.count, label: "신고", tone: AppColors.danger)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            } header: {
                Text("통계")
            } footer: {
                Text("‘현재 활동’은 최근 2분 내 사용(presence) 근사치 · 진짜 동시접속은 Realtime 필요")
            }
            Section("공지") {
                Button {
                    composingAnnouncement = true
                } label: {
                    Label("새 공지 작성", systemImage: "megaphone")
                }
                ForEach(announcements) { a in
                    NavigationLink {
                        AdminAnnouncementSheet(existing: a) { await reloadAnnouncements() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.body).font(.system(size: 13)).lineLimit(1)
                            Text(announcementPeriod(a) + (a.active ? "" : " · 비활성"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteAnnouncement(a) }
                        } label: { Label("삭제", systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteAnnouncements(at: offsets) }
                }
                if announcements.isEmpty {
                    Text("작성한 공지 없음").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("큐레이션 영상 채널") {
                Button { composingChannel = true } label: {
                    Label("새 채널 추가", systemImage: "play.rectangle")
                }
                ForEach(channels) { ch in
                    NavigationLink {
                        AdminChannelSheet(existing: ch) { await reloadChannels() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.title).font(.system(size: 13)).lineLimit(1)
                            Text("\(ch.locale.uppercased()) · \(ch.channelID)" + (ch.active ? "" : " · 비활성"))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteChannel(ch) }
                        } label: { Label("삭제", systemImage: "trash") }
                    }
                }
                if channels.isEmpty {
                    Text("등록된 채널 없음").font(.caption).foregroundStyle(.secondary)
                }
                Text("YouTube 채널 ID(UCxxxx)를 언어별로 등록. 채널 RSS로 신규 영상을 분석 탭 ‘영상’에 표시.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("채널 제안 (사용자)") {
                if suggestions.isEmpty {
                    Text("받은 제안 없음").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            if let link = URL(string: s.url) {
                                Link(s.url, destination: link)
                                    .font(.system(size: 13)).lineLimit(2)
                            } else {
                                Text(s.url).font(.system(size: 13)).lineLimit(2)
                            }
                            if let note = s.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Text(s.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteSuggestion(s) }
                            } label: { Label("삭제", systemImage: "trash") }
                        }
                    }
                }
            }
            Section("신고된 게시물") {
                if grouped.isEmpty {
                    Text(loaded
                         ? "신고된 게시물 없음 (또는 admin RLS 미배포 — docs/community/admin_ops.sql)"
                         : "불러오는 중…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grouped) { g in
                        if let post = reportedPosts[g.postID] {
                            NavigationLink {
                                AdminPostDetailView(post: post, reportCount: g.count, reasons: g.reasons) { await reload() }
                            } label: { reportRow(g) }
                        } else {
                            reportRow(g)
                        }
                    }
                }
            }
        }
        .navigationTitle("운영 대시보드")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
        .sheet(isPresented: $composingAnnouncement) {
            NavigationStack {
                AdminAnnouncementSheet(existing: nil) { await reloadAnnouncements() }
            }
        }
        .sheet(isPresented: $composingChannel) {
            NavigationStack {
                AdminChannelSheet(existing: nil) { await reloadChannels() }
            }
        }
    }

    private func reloadChannels() async {
        channels = await service.fetchAllCuratedChannels()
    }

    private func deleteChannel(_ ch: Community.CuratedChannel) async {
        channels.removeAll { $0.id == ch.id }
        if !(await service.deleteCuratedChannel(id: ch.id)) { await reloadChannels() }
    }

    private func deleteSuggestion(_ s: Community.ChannelSuggestion) async {
        suggestions.removeAll { $0.id == s.id }
        if !(await service.deleteChannelSuggestion(id: s.id)) {
            suggestions = await service.fetchChannelSuggestions()
        }
    }

    @ViewBuilder
    private func reportRow(_ g: ReportGroup) -> some View {
        let post = reportedPosts[g.postID]
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(AppColors.paper2)
                if let post, let url = service.imageURL(for: post.imagePath) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo").foregroundStyle(AppColors.ink3)
                }
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(post?.authorName ?? "—").font(.system(size: 13, weight: .semibold))
                    if let st = post?.status, st != .approved {
                        Text(st == .hidden ? "숨김" : "차단")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                    }
                }
                if let cap = post?.caption, !cap.isEmpty {
                    Text(cap).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("신고 \(g.count)건 · \(g.reasons.joined(separator: ", "))")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func reload() async {
        async let s = service.fetchOpsStats()
        async let r = service.fetchReports()
        async let a = service.fetchAnnouncements()
        async let c = service.fetchAllCuratedChannels()
        async let sg = service.fetchChannelSuggestions()
        stats = await s
        let rep = await r
        reports = rep
        announcements = await a
        channels = await c
        suggestions = await sg
        let ids = Array(Set(rep.map { $0.postID }))
        let posts = await service.fetchReportedPosts(ids: ids)
        reportedPosts = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        loaded = true
    }

    private func reloadAnnouncements() async {
        announcements = await service.fetchAnnouncements()
    }

    /// swipe(전체삭제 버튼) — 단건 삭제. 낙관적 제거 후 서버 삭제, 실패 시 reload 로 복구.
    private func deleteAnnouncement(_ a: Community.Announcement) async {
        announcements.removeAll { $0.id == a.id }
        if !(await service.deleteAnnouncement(id: a.id)) {
            await reloadAnnouncements()
        }
    }

    /// onDelete(IndexSet) — 다건 삭제.
    private func deleteAnnouncements(at offsets: IndexSet) async {
        let targets = offsets.map { announcements[$0] }
        announcements.remove(atOffsets: offsets)
        var failed = false
        for t in targets where !(await service.deleteAnnouncement(id: t.id)) { failed = true }
        if failed { await reloadAnnouncements() }
    }

    private func announcementPeriod(_ a: Community.Announcement) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"
        let s = a.startsAt.map { f.string(from: $0) } ?? "—"
        let e = a.endsAt.map { f.string(from: $0) } ?? "—"
        return "\(s) ~ \(e)"
    }
}

/// 운영 통계 타일 — 아이콘 + 큰 숫자 + 라벨.
private struct AdminStatTile: View {
    let icon: String
    let value: Int
    let label: String
    let tone: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tone)
            Text("\(value)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(AppColors.ink0)
            Text(label).font(.system(size: 11)).foregroundStyle(AppColors.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(8)
        .background(tone.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 신고 게시물 상세 — 본문 + 숨김/삭제 + 작성자 경고.
private struct AdminPostDetailView: View {
    let post: Community.Post
    let reportCount: Int
    let reasons: [String]
    let onChanged: () async -> Void
    private let service = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var warning = ""
    @State private var sending = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                if let url = service.imageURL(for: post.imagePath) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { AppColors.paper2.frame(height: 220) }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("게시물") {
                LabeledContent("작성자", value: post.authorName ?? "—")
                if let cap = post.caption, !cap.isEmpty { Text(cap) }
                LabeledContent("상태", value: post.status.rawValue)
                Text("신고 \(reportCount)건 · \(reasons.joined(separator: ", "))").font(.caption).foregroundStyle(.red)
            }
            Section("조치") {
                Button { Task { _ = await service.adminHidePost(post.id); await onChanged(); dismiss() } } label: {
                    Label("숨김 처리", systemImage: "eye.slash")
                }
                Button(role: .destructive) { Task { _ = await service.adminDeletePost(post); await onChanged(); dismiss() } } label: {
                    Label("게시물 삭제", systemImage: "trash")
                }
            }
            Section("작성자에게 경고") {
                TextField("경고 메시지", text: $warning, axis: .vertical).lineLimit(2...5)
                Button {
                    sending = true
                    Task {
                        let ok = await service.sendWarning(toUID: post.authorUID, message: warning)
                        toast = ok ? "⚠️ 경고 발송됨" : "발송 실패 (admin RLS 확인)"
                        warning = ""
                        sending = false
                    }
                } label: { Label("경고 보내기", systemImage: "exclamationmark.bubble") }
                .disabled(warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                if let toast { Text(toast).font(.caption).foregroundStyle(AppColors.success) }
            }
        }
        .navigationTitle("신고 게시물")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 공지 작성·수정 — 내용 + 노출 기간(시작/종료) + 활성.
private struct AdminAnnouncementSheet: View {
    let existing: Community.Announcement?
    let onSaved: () async -> Void
    private let service = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ""
    @State private var startsAt = Date()
    @State private var endsAt = Date().addingTimeInterval(7 * 86400)
    @State private var active = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("내용") {
                TextField("공지 내용", text: $bodyText, axis: .vertical).lineLimit(3...8)
            }
            Section("노출 기간") {
                DatePicker("시작", selection: $startsAt)
                DatePicker("종료", selection: $endsAt)
                Toggle("활성", isOn: $active)
            }
            Section {
                Button(existing == nil ? "발송" : "수정 저장") {
                    saving = true
                    Task {
                        let ok: Bool
                        if let e = existing {
                            ok = await service.updateAnnouncement(id: e.id, body: bodyText, startsAt: startsAt, endsAt: endsAt, active: active)
                        } else {
                            ok = await service.postAnnouncement(body: bodyText, startsAt: startsAt, endsAt: endsAt)
                        }
                        saving = false
                        if ok { await onSaved(); dismiss() } else { error = "저장 실패 (admin RLS 확인)" }
                    }
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(existing == nil ? "공지 작성" : "공지 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        .onAppear {
            if let e = existing {
                bodyText = e.body
                startsAt = e.startsAt ?? Date()
                endsAt = e.endsAt ?? Date().addingTimeInterval(7 * 86400)
                active = e.active
            }
        }
    }
}

/// 큐레이션 YouTube 채널 추가/수정 — 채널 ID(UCxxxx)·채널명·언어·정렬·활성.
private struct AdminChannelSheet: View {
    let existing: Community.CuratedChannel?
    let onSaved: () async -> Void
    private let service = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var channelID = ""
    @State private var title = ""
    @State private var thumbnailURL = ""
    @State private var locale = "en"
    @State private var category = ""
    @State private var sortOrder = 0
    @State private var active = true
    @State private var saving = false
    @State private var error: String?

    private let locales = ["ko", "en", "ja", "zh-Hans", "zh-Hant", "es", "hi", "fr"]
    private var canSave: Bool {
        !channelID.trimmingCharacters(in: .whitespaces).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        Form {
            Section("채널") {
                TextField("채널 ID · @핸들 · URL", text: $channelID)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("채널명", text: $title)
                TextField("썸네일 URL (선택)", text: $thumbnailURL)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section("노출") {
                Picker("언어", selection: $locale) {
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }
                TextField("카테고리 (선택: review/news…)", text: $category).autocorrectionDisabled()
                Stepper("정렬 순서: \(sortOrder)", value: $sortOrder, in: 0...999)
                Toggle("활성", isOn: $active)
            }
            Section {
                Button(existing == nil ? "추가" : "수정 저장") {
                    saving = true
                    error = nil
                    Task {
                        // @핸들·URL·UCxxxx 모두 받아 RSS용 채널 ID(UCxxxx)로 변환.
                        guard let cid = await YouTubeFeedService.resolveChannelID(from: channelID) else {
                            saving = false
                            error = "채널 ID를 찾지 못했어요. @핸들·채널 URL이 정확한지 확인하거나 UCxxxx를 직접 입력하세요."
                            return
                        }
                        let ok: Bool
                        if let e = existing {
                            ok = await service.updateCuratedChannel(id: e.id, channelID: cid, title: title, thumbnailURL: thumbnailURL, locale: locale, category: category, sortOrder: sortOrder, active: active)
                        } else {
                            ok = await service.addCuratedChannel(channelID: cid, title: title, thumbnailURL: thumbnailURL, locale: locale, category: category, sortOrder: sortOrder)
                        }
                        saving = false
                        if ok { await onSaved(); dismiss() }
                        else { error = service.lastError ?? "저장 실패 (admin RLS·channel_id 확인)" }
                    }
                }
                .disabled(!canSave)
                if saving {
                    HStack(spacing: 8) { ProgressView(); Text("채널 ID 변환·저장 중…").font(.caption).foregroundStyle(.secondary) }
                }
                Text("@핸들·채널 URL·UCxxxx 모두 가능 — 자동으로 채널 ID로 변환합니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(existing == nil ? "채널 추가" : "채널 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        .onAppear {
            if let e = existing {
                channelID = e.channelID; title = e.title; thumbnailURL = e.thumbnailURL ?? ""
                locale = e.locale; category = e.category ?? ""; sortOrder = e.sortOrder; active = e.active
            }
        }
    }
}

private struct AdminPanelView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var seedToast: String? = nil
    /// 운영 ID — ON 이면 커뮤니티 게시 시 닉네임 'TickLab' + 앱 아이콘 아바타로 표시.
    /// ⚠️ 클라 편의용. 위조 방지는 Supabase RLS 필요(docs/community/admin_rls.sql).
    @AppStorage("ticklab.admin.actingAsTickLab") private var actingAsTickLab = false
    /// admin_users 등록용 — 내 커뮤니티 uid 표시/복사.
    @ObservedObject private var community = CommunityService.shared

    var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            Form {
                Section("운영 ID") {
                    Picker("커뮤니티 게시 신원", selection: $actingAsTickLab) {
                        Text("사용자").tag(false)
                        Text("관리자 (TickLab)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(actingAsTickLab
                         ? "커뮤니티 게시 시 닉네임 'TickLab' + 앱 아이콘 아바타로 표시됩니다. (서버 RLS 적용 시 admin 등록 필수)"
                         : "일반 사용자 프로필 이름으로 게시됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Supabase admin_users 등록용 — 내 uid 복사.
                    if let uid = community.myUID, !uid.isEmpty {
                        Button {
                            UIPasteboard.general.string = uid
                            seedToast = "📋 내 UID 복사됨 — Supabase admin_users 에 등록하세요"
                        } label: {
                            Label("내 커뮤니티 UID 복사", systemImage: "doc.on.doc")
                        }
                        Text(uid)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("커뮤니티 탭에 한 번 들어가 로그인하면 UID가 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    NavigationLink {
                        AdminOpsView()
                    } label: {
                        Label("운영 대시보드 (신고·통계·활동)", systemImage: "shield.lefthalf.filled")
                    }
                    if let toast = seedToast {
                        Text(toast).font(.caption).foregroundStyle(.green)
                    }
                }
                Section("라이선스 모드") {
                    Toggle("Pro 잠금 해제", isOn: Binding(
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
            }
            .navigationTitle("관리자 패널")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
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
