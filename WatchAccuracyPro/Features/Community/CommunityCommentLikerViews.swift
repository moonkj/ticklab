import SwiftUI
import UIKit

/// 커뮤니티 댓글 — 목록 + 작성(욕설·거래 필터) + 삭제(본인/운영자). 차단 작성자 댓글은 service가 제외.
struct CommentsView: View {
    let post: Community.Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = CommunityService.shared
    @AppStorage("ticklab.admin.actingAsTickLab") private var actingAsTickLab = false
    @State private var comments: [Community.Comment] = []
    @State private var input = ""
    @State private var sending = false
    @State private var loaded = false
    @State private var blockMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loaded && comments.isEmpty {
                    EmptyState(
                        icon: "bubble.right",
                        title: String(localized: "community.comment.title"),
                        message: String(localized: "community.comment.empty")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(comments) { c in commentRow(c) }
                        }
                        .padding(16)
                    }
                }
                Divider()
                inputBar
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "community.comment.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .task { await reload() }
            .alert(String(localized: "text.filter.blocked.title"),
                   isPresented: Binding(get: { blockMessage != nil }, set: { if !$0 { blockMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(blockMessage ?? "") }
        }
    }

    private func commentRow(_ c: Community.Comment) -> some View {
        let canDelete = c.isMine(service.myUID) || actingAsTickLab
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                if c.authorName == "TickLab", let icon = AppIconProvider.image {
                    Image(uiImage: icon).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Circle().fill(AppColors.paper2)
                    Text(String((c.authorName ?? "C").first.map(String.init) ?? "C").uppercased())
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(AppColors.ink2)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.authorName ?? String(localized: "community.anon_handle"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.ink0)
                    Text(c.createdAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11)).foregroundStyle(AppColors.ink3)
                }
                Text(c.body).font(.system(size: 14)).foregroundStyle(AppColors.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if canDelete {
                Button { Task { await delete(c) } } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(AppColors.ink3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(String(localized: "community.comment.placeholder"), text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppColors.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Button { submit() } label: {
                if sending { ProgressView() }
                else { Text(String(localized: "community.comment.post")).font(.system(size: 15, weight: .semibold)) }
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func reload() async {
        comments = await service.fetchComments(postID: post.id)
        loaded = true
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch CommunityTextModerator.screen(text) {
        case .allowed: break
        case .tooLong:  blockMessage = String(localized: "community.comment.too_long"); return
        case .profane:  blockMessage = String(localized: "community.comment.profane"); return
        case .tradeBan: blockMessage = String(localized: "community.comment.trade"); return
        }
        sending = true
        Task {
            let ok = await service.addComment(to: post, body: text)
            sending = false
            if ok { input = ""; focused = false; service.adjustLocalCommentCount(post.id, delta: +1); await reload() }
        }
    }

    private func delete(_ c: Community.Comment) async {
        comments.removeAll { $0.id == c.id }
        if await service.deleteComment(c.id) {
            service.adjustLocalCommentCount(post.id, delta: -1)
        } else {
            await reload()
        }
    }
}

/// 좋아요 라이커 목록(인스타 "누가 좋아요") — 이름 탭하면 그 사람 게시물, 옆에 팔로우 토글.
struct LikersView: View {
    let post: Community.Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = CommunityService.shared
    @State private var likers: [Community.Liker] = []
    @State private var loaded = false
    @State private var profileTarget: Community.Liker?

    var body: some View {
        NavigationStack {
            Group {
                if loaded && likers.isEmpty {
                    EmptyState(
                        icon: "heart",
                        title: String(localized: "community.likers.title"),
                        message: String(localized: "community.likers.empty")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(likers) { liker in
                                row(liker)
                                Divider().padding(.leading, 62)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationTitle(String(localized: "community.likers.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .navigationDestination(item: $profileTarget) { liker in
                UserPostsView(uid: liker.uid, displayName: liker.authorName)
            }
            .task { likers = await service.fetchLikers(postID: post.id); loaded = true }
        }
    }

    private func row(_ liker: Community.Liker) -> some View {
        let isMe = liker.uid == service.myUID
        let following = service.isFollowing(liker.uid)
        return HStack(spacing: 12) {
            // 이름·아바타 탭 → 그 사람 게시물(NavigationLink 미사용 — 버튼이 가로 확장돼 팔로우를 밀어내는 문제 회피).
            Button { profileTarget = liker } label: {
                LikerAvatar(name: liker.authorName).frame(width: 34, height: 34)
                Text(liker.authorName ?? String(localized: "community.anon_handle"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.ink0)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if !isMe {
                Button { Task { await service.toggleFollow(liker.uid) } } label: {
                    Text(String(localized: following ? "community.following" : "community.follow"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(following ? AppColors.ink2 : AppColors.paper0)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(following ? Color.clear : AppColors.ink0)
                        .overlay(Capsule().stroke(following ? AppColors.rule : Color.clear, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// 라이커/작성자 아바타 — TickLab은 앱 아이콘, 그 외 이니셜.
struct LikerAvatar: View {
    let name: String?
    var body: some View {
        ZStack {
            if name == "TickLab", let icon = AppIconProvider.image {
                Image(uiImage: icon).resizable().scaledToFill().clipShape(Circle())
            } else {
                Circle().fill(AppColors.paper2)
                Text(String((name ?? "C").first.map(String.init) ?? "C").uppercased())
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(AppColors.ink2)
            }
        }
    }
}

