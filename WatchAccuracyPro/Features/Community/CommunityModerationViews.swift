import SwiftUI
import UIKit

/// 차단 관리 — 사용자가 차단한 작성자 목록 + 차단 해제.
/// 익명 커뮤니티라 닉네임이 없어 UID 끝 4자리로만 구분 표기(본인만 보는 본인 데이터).
struct BlockedUsersView: View {
    @ObservedObject private var service = CommunityService.shared
    @Environment(\.dismiss) private var dismiss

    /// 본인 uid 는 제외(자기차단 방어) — 끝 4자리 정렬.
    private var blockedList: [String] {
        service.blockedUIDs.filter { $0 != service.myUID }.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if blockedList.isEmpty {
                    Section {
                        Text(String(localized: "community.blocked.empty"))
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.ink3)
                    }
                } else {
                    Section {
                        ForEach(blockedList, id: \.self) { uid in
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppColors.ink3)
                                Text(blockedLabel(uid))
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppColors.ink0)
                                Spacer()
                                Button(String(localized: "community.blocked.unblock")) {
                                    Task { await service.unblock(uid) }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.accent)
                                .buttonStyle(.borderless)
                            }
                        }
                    } footer: {
                        Text(String(localized: "community.blocked.footer"))
                    }
                }
            }
            .navigationTitle(String(localized: "community.blocked.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }

    private func blockedLabel(_ uid: String) -> String {
        String(localized: "community.blocked.anon") + " #" + uid.suffix(4)
    }
}

/// 활동 알림 목록(컬렉션 종) — 내 글 좋아요 · 새 팔로워. 익명 커뮤니티라 행위자명은 비표시.
struct CommunityNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [Community.Notice] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if loaded && notices.isEmpty {
                    EmptyState(
                        icon: "bell.slash",
                        title: String(localized: "collection.notifications"),
                        message: String(localized: "community.notif.empty")
                    )
                } else {
                    List(notices) { notice in
                        row(notice)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppColors.paper0)
            .navigationTitle(String(localized: "collection.notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .task {
                notices = await CommunityService.shared.fetchNotifications()
                loaded = true
                CommunityService.shared.markNotificationsSeen()
            }
        }
    }

    private func row(_ n: Community.Notice) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((n.kind == .like ? AppColors.danger : AppColors.accent).opacity(0.14))
                Image(systemName: n.kind == .like ? "heart.fill" : "person.fill.badge.plus")
                    .font(.system(size: 15))
                    .foregroundStyle(n.kind == .like ? AppColors.danger : AppColors.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: n.kind == .like ? "community.notif.like" : "community.notif.follow"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.ink0)
                Text(Self.relative.localizedString(for: n.createdAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(AppColors.ink3)
            }
            Spacer()
            if let path = n.postImagePath, let url = CommunityService.shared.imageURL(for: path) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Color(AppColors.paper2) }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()
}

