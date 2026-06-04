import SwiftUI
import SwiftData
import UIKit

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
    @State private var composingTheme = false
    @State private var announcements: [Community.Announcement] = []
    @State private var composingChannel = false
    @State private var channels: [Community.CuratedChannel] = []
    @State private var suggestions: [Community.ChannelSuggestion] = []
    @State private var feedback: [Community.Feedback] = []

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
                    AdminStatTile(icon: "person.2.fill", value: stats.activeUsers, label: String(localized: "admin.stats.active_users"), tone: AppColors.accent)
                    AdminStatTile(icon: "calendar", value: stats.todayPosts, label: String(localized: "admin.stats.today_posts"), tone: AppColors.info)
                    AdminStatTile(icon: "square.grid.2x2", value: stats.totalPosts, label: String(localized: "admin.stats.total_posts"), tone: AppColors.ink2)
                    AdminStatTile(icon: "flag.fill", value: grouped.count, label: String(localized: "admin.stats.reports"), tone: AppColors.danger)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            } header: {
                Text(String(localized: "admin.stats.section"))
            } footer: {
                Text(String(localized: "admin.stats.footer"))
            }
            Section(String(localized: "admin.notice.section")) {
                Button {
                    composingAnnouncement = true
                } label: {
                    Label(String(localized: "admin.notice.new"), systemImage: "megaphone")
                }
                Button {
                    composingTheme = true
                } label: {
                    Label(String(localized: "admin.theme.new"), systemImage: "sparkles")
                }
                ForEach(announcements) { a in
                    NavigationLink {
                        AdminAnnouncementSheet(existing: a) { await reloadAnnouncements() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.body).font(.system(size: 13)).lineLimit(1)
                            Text(announcementPeriod(a) + (a.active ? "" : " · " + String(localized: "admin.toggle.inactive")))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteAnnouncement(a) }
                        } label: { Label(String(localized: "common.delete"), systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    Task { await deleteAnnouncements(at: offsets) }
                }
                if announcements.isEmpty {
                    Text(String(localized: "admin.notice.empty")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "admin.channel.section")) {
                Button { composingChannel = true } label: {
                    Label(String(localized: "admin.channel.new"), systemImage: "play.rectangle")
                }
                ForEach(channels) { ch in
                    NavigationLink {
                        AdminChannelSheet(existing: ch) { await reloadChannels() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.title).font(.system(size: 13)).lineLimit(1)
                            Text("\(ch.locale.uppercased()) · \(ch.channelID)" + (ch.active ? "" : " · " + String(localized: "admin.toggle.inactive")))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteChannel(ch) }
                        } label: { Label(String(localized: "common.delete"), systemImage: "trash") }
                    }
                }
                if channels.isEmpty {
                    Text(String(localized: "admin.channel.empty")).font(.caption).foregroundStyle(.secondary)
                }
                Text(String(localized: "admin.channel.hint"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section(String(localized: "admin.suggestion.section")) {
                if suggestions.isEmpty {
                    Text(String(localized: "admin.suggestion.empty")).font(.caption).foregroundStyle(.secondary)
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
                            } label: { Label(String(localized: "common.delete"), systemImage: "trash") }
                        }
                    }
                }
            }
            Section(String(localized: "admin.feedback.section")) {
                if feedback.isEmpty {
                    Text(String(localized: "admin.feedback.empty")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(feedback) { f in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feedbackTypeLabel(f.type))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppColors.accentDark)
                            Text(f.message).font(.system(size: 13)).lineLimit(6)
                            HStack(spacing: 6) {
                                if let v = f.appVersion { Text("v\(v)") }
                                Text(f.createdAt.formatted(.relative(presentation: .named)))
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteFeedbackItem(f) }
                            } label: { Label(String(localized: "common.delete"), systemImage: "trash") }
                        }
                    }
                }
            }
            Section(String(localized: "admin.report.section")) {
                if grouped.isEmpty {
                    Text(loaded
                         ? String(localized: "admin.report.empty")
                         : String(localized: "community.loading"))
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
        .navigationTitle(String(localized: "admin.dashboard.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
        .sheet(isPresented: $composingAnnouncement) {
            NavigationStack {
                AdminAnnouncementSheet(existing: nil) { await reloadAnnouncements() }
            }
        }
        .sheet(isPresented: $composingTheme) {
            NavigationStack {
                AdminThemeSheet { await reloadAnnouncements() }
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

    private func deleteFeedbackItem(_ f: Community.Feedback) async {
        feedback.removeAll { $0.id == f.id }
        if !(await service.deleteFeedback(id: f.id)) {
            feedback = await service.fetchFeedback()
        }
    }

    private func feedbackTypeLabel(_ raw: String) -> String {
        switch raw {
        case "bug":        return String(localized: "feedback.type.bug")
        case "suggestion": return String(localized: "feedback.type.suggestion")
        default:           return String(localized: "feedback.type.general")
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
                        Text(st == .hidden ? String(localized: "admin.report.post.hidden") : String(localized: "admin.report.post.blocked"))
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                    }
                }
                if let cap = post?.caption, !cap.isEmpty {
                    Text(cap).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(String(format: String(localized: "admin.report.count"), g.count, g.reasons.joined(separator: ", ")))
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
        async let fb = service.fetchFeedback()
        stats = await s
        let rep = await r
        reports = rep
        announcements = await a
        channels = await c
        suggestions = await sg
        feedback = await fb
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
            Section(String(localized: "admin.post.section")) {
                LabeledContent(String(localized: "admin.post.author"), value: post.authorName ?? "—")
                if let cap = post.caption, !cap.isEmpty { Text(cap) }
                LabeledContent(String(localized: "admin.post.status"), value: post.status.rawValue)
                Text(String(format: String(localized: "admin.report.count"), reportCount, reasons.joined(separator: ", "))).font(.caption).foregroundStyle(.red)
            }
            Section(String(localized: "admin.action.section")) {
                Button { Task { _ = await service.adminHidePost(post.id); await onChanged(); dismiss() } } label: {
                    Label(String(localized: "admin.action.hide"), systemImage: "eye.slash")
                }
                Button(role: .destructive) { Task { _ = await service.adminDeletePost(post); await onChanged(); dismiss() } } label: {
                    Label(String(localized: "admin.action.delete_post"), systemImage: "trash")
                }
            }
            Section(String(localized: "admin.warning.section")) {
                TextField(String(localized: "admin.warning.placeholder"), text: $warning, axis: .vertical).lineLimit(2...5)
                Button {
                    sending = true
                    Task {
                        let ok = await service.sendWarning(toUID: post.authorUID, message: warning)
                        toast = ok ? "⚠️ 경고 발송됨" : "발송 실패 (admin RLS 확인)"
                        warning = ""
                        sending = false
                    }
                } label: { Label(String(localized: "admin.warning.send"), systemImage: "exclamationmark.bubble") }
                .disabled(warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                if let toast { Text(toast).font(.caption).foregroundStyle(AppColors.success) }
            }
        }
        .navigationTitle(String(localized: "admin.report.detail.title"))
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
            Section(String(localized: "admin.notice.content.section")) {
                TextField(String(localized: "admin.notice.content.placeholder"), text: $bodyText, axis: .vertical).lineLimit(3...8)
            }
            Section(String(localized: "admin.notice.period.section")) {
                DatePicker(String(localized: "admin.notice.period.start"), selection: $startsAt)
                DatePicker(String(localized: "admin.notice.period.end"), selection: $endsAt)
                Toggle(String(localized: "admin.toggle.active"), isOn: $active)
            }
            Section {
                Button(existing == nil ? String(localized: "admin.notice.send") : String(localized: "admin.notice.update")) {
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
        .navigationTitle(existing == nil ? String(localized: "admin.notice.compose.title") : String(localized: "admin.notice.edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } } }
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

/// 위클리 테마 발행 — 제목 + 노출 기간. kind='theme' 공지로 게시(postWeeklyTheme).
private struct AdminThemeSheet: View {
    let onSaved: () async -> Void
    private let service = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = Date()
    @State private var endsAt = Date().addingTimeInterval(7 * 86400)
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section(String(localized: "admin.theme.title.label")) {
                TextField(String(localized: "admin.theme.title.placeholder"), text: $title)
            }
            Section(String(localized: "admin.notice.period.section")) {
                DatePicker(String(localized: "admin.notice.period.start"), selection: $startsAt)
                DatePicker(String(localized: "admin.notice.period.end"), selection: $endsAt)
            }
            Section {
                Button(String(localized: "admin.theme.publish")) {
                    saving = true
                    Task {
                        let ok = await service.postWeeklyTheme(title: title, body: nil, startsAt: startsAt, endsAt: endsAt)
                        saving = false
                        if ok { await onSaved(); dismiss() } else { error = "발행 실패 (admin RLS 확인)" }
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(String(localized: "admin.theme.compose.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } } }
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
            Section(String(localized: "admin.channel.form.section")) {
                TextField(String(localized: "admin.channel.id.placeholder"), text: $channelID)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField(String(localized: "admin.channel.name.placeholder"), text: $title)
                TextField(String(localized: "admin.channel.thumbnail.placeholder"), text: $thumbnailURL)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section(String(localized: "admin.channel.display.section")) {
                Picker(String(localized: "admin.channel.locale.label"), selection: $locale) {
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }
                TextField(String(localized: "admin.channel.category.placeholder"), text: $category).autocorrectionDisabled()
                Stepper(String(format: String(localized: "admin.channel.sort_order"), sortOrder), value: $sortOrder, in: 0...999)
                Toggle(String(localized: "admin.toggle.active"), isOn: $active)
            }
            Section {
                Button(existing == nil ? String(localized: "admin.channel.add") : String(localized: "admin.notice.update")) {
                    saving = true
                    error = nil
                    Task {
                        // @핸들·URL·UCxxxx 모두 받아 RSS용 채널 ID(UCxxxx)로 변환.
                        guard let cid = await YouTubeFeedService.resolveChannelID(from: channelID) else {
                            saving = false
                            error = String(localized: "admin.channel.resolve_error")
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
                    HStack(spacing: 8) { ProgressView(); Text(String(localized: "admin.channel.saving")).font(.caption).foregroundStyle(.secondary) }
                }
                Text(String(localized: "admin.channel.format_hint"))
                    .font(.caption2).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(existing == nil ? String(localized: "admin.channel.add.title") : String(localized: "admin.channel.edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } } }
        .onAppear {
            if let e = existing {
                channelID = e.channelID; title = e.title; thumbnailURL = e.thumbnailURL ?? ""
                locale = e.locale; category = e.category ?? ""; sortOrder = e.sortOrder; active = e.active
            }
        }
    }
}

struct AdminPanelView: View {
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
                Section(String(localized: "admin.ops_id.section")) {
                    Picker(String(localized: "admin.ops_id.identity.label"), selection: $actingAsTickLab) {
                        Text(String(localized: "admin.ops_id.user")).tag(false)
                        Text(String(localized: "admin.ops_id.admin")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(actingAsTickLab
                         ? String(localized: "admin.ops_id.hint.admin")
                         : String(localized: "admin.ops_id.hint.user"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Supabase admin_users 등록용 — 내 uid 복사.
                    if let uid = community.myUID, !uid.isEmpty {
                        Button {
                            UIPasteboard.general.string = uid
                            seedToast = "📋 내 UID 복사됨 — Supabase admin_users 에 등록하세요"
                        } label: {
                            Label(String(localized: "admin.ops_id.copy_uid"), systemImage: "doc.on.doc")
                        }
                        Text(uid)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(String(localized: "admin.ops_id.uid_hint"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    NavigationLink {
                        AdminOpsView()
                    } label: {
                        Label(String(localized: "admin.ops_id.dashboard_link"), systemImage: "shield.lefthalf.filled")
                    }
                    if let toast = seedToast {
                        Text(toast).font(.caption).foregroundStyle(.green)
                    }
                }
                Section(String(localized: "admin.license.section")) {
                    Toggle(String(localized: "admin.license.pro_unlock"), isOn: Binding(
                        get: { prefs.isPro },
                        set: { newValue in
                            prefs.isPro = newValue
                            ProEntitlement.shared.markPro(newValue)
                        }
                    ))
                    Text(prefs.isPro
                         ? String(localized: "admin.license.status.pro")
                         : String(format: String(localized: "admin.license.status.free"), ProEntitlement.freeWatchLimit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "admin.panel.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}

#endif
// } Round 138 끝 / Round 149 (Hyemi 7 C3) — AdminPanel #if DEBUG 가드
