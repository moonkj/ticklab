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
    @State private var showingCommunityGuidelines: Bool = false
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
                                        Text(String(localized: "profile.badge.dealer"))
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
                    // 커뮤니티 가이드라인(약관) — 인앱 상시 열람 (App Store 1.2). EULA뷰 읽기전용 재사용.
                    Button { showingCommunityGuidelines = true } label: {
                        HStack {
                            Text(String(localized: "settings.help.community_guidelines"))
                            Spacer()
                            Image(systemName: "person.2")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink3)
                        }
                    }
                    .sheet(isPresented: $showingCommunityGuidelines) {
                        CommunityEULAView(reviewOnly: true) {}
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
            .alert(String(localized: "admin.access.title"), isPresented: $showingAdminPinPrompt) {
                SecureField("PIN", text: $adminPinInput)
                    .keyboardType(.numberPad)
                Button(String(localized: "admin.access.submit")) {
                    if adminPinInput == "1639316" {
                        adminPinInput = ""
                        showingAdminPanel = true
                    } else {
                        adminPinError = true
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    adminPinInput = ""
                }
            } message: {
                Text(adminPinError ? String(localized: "admin.access.pin_wrong") : String(localized: "admin.access.pin_prompt"))
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


#Preview {
    SettingsView()
        .environment(UserPreferences())
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
