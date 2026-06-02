import SwiftUI
import UIKit

/// 특정 사용자의 게시물 그리드(인스타 프로필 격자) + 팔로우. 익명 닉네임 표시.
struct UserPostsView: View {
    let uid: String
    let displayName: String?
    @ObservedObject private var service = CommunityService.shared
    @State private var posts: [Community.Post] = []
    @State private var loaded = false
    @State private var showLogin = false

    private let cols = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    LikerAvatar(name: displayName).frame(width: 56, height: 56)
                    Text(displayName ?? String(localized: "community.anon_handle"))
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(AppColors.ink0)
                    Spacer()
                    if uid != service.myUID {
                        let following = service.isFollowing(uid)
                        Button {
                            guard service.isSignedIn else { showLogin = true; return }   // 감사 수정: 미로그인 조용한 팔로우 실패 방지
                            Task { await service.toggleFollow(uid) }
                        } label: {
                            Text(String(localized: following ? "community.following" : "community.follow"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(following ? AppColors.ink2 : AppColors.paper0)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(following ? Color.clear : AppColors.ink0)
                                .overlay(Capsule().stroke(following ? AppColors.rule : Color.clear, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)

                if loaded && posts.isEmpty {
                    Text(String(localized: "community.user.empty"))
                        .font(.system(size: 14)).foregroundStyle(AppColors.ink3)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 2) {
                        ForEach(posts) { p in
                            // 사진 탭 → 그 게시물 상세로 이동.
                            NavigationLink {
                                PostDetailView(post: p)
                            } label: {
                                Color(AppColors.paper2)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        if p.imagePath == nil {
                                            // Round 171 글-전용 — 그리드엔 텍스트 발췌 타일.
                                            Text(p.caption ?? "")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppColors.ink2)
                                                .lineLimit(4)
                                                .multilineTextAlignment(.leading)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                                .overlay(alignment: .bottomTrailing) {
                                                    Image(systemName: "text.alignleft")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(AppColors.ink3)
                                                        .padding(6)
                                                }
                                        } else {
                                            AsyncImage(url: service.imageURL(for: p.imagePath)) { phase in
                                                switch phase {
                                                case .success(let img): img.resizable().scaledToFill()
                                                default: Color.clear
                                                }
                                            }
                                        }
                                    }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(displayName ?? String(localized: "community.anon_handle"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { CommunityLoginView() }
        .task { posts = await service.fetchPostsByAuthor(uid: uid); loaded = true }
    }
}

/// 단일 게시물 상세 — 프로필 그리드/딥링크에서 진입. 피드 카드(좋아요·댓글·라이커·공유)를 그대로 재사용.
struct PostDetailView: View {
    let post: Community.Post
    @ObservedObject private var service = CommunityService.shared
    @State private var commentTarget: Community.Post?
    @State private var likersTarget: Community.Post?
    @State private var shareItem: ShareCardItem?
    @State private var reportDone = false
    @State private var showLogin = false

    var body: some View {
        ScrollView {
            CommunityPostCard(
                post: post,
                liked: service.isLiked(post),
                blurred: false,
                following: service.isFollowing(post.authorUID),
                bookmarked: service.isBookmarked(post),
                isMine: post.isMine(currentUID: service.myUID),
                onLike: { guard service.isSignedIn else { showLogin = true; return }; Task { await service.toggleLike(post) } },
                onUnlock: {},
                onReport: { reason in
                    guard service.isSignedIn else { showLogin = true; return }   // 감사 수정: 미로그인 거짓 "신고 완료" 방지
                    Task { await service.report(post, reason: reason); reportDone = true }
                },
                onBlock: { Task { await service.block(authorOf: post) } },
                onFollow: { guard service.isSignedIn else { showLogin = true; return }; Task { await service.toggleFollow(post.authorUID) } },
                onBookmark: { guard service.isSignedIn else { showLogin = true; return }; Task { await service.toggleBookmark(post) } },
                onShare: { if let url = service.imageURL(for: post.imagePath) { shareItem = ShareCardItem(url: url) } },
                onComment: { commentTarget = post },
                onLikers: { likersTarget = post },
                onDelete: nil
            )
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(post.authorName ?? String(localized: "community.anon_handle"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $commentTarget) { CommentsView(post: $0) }
        .sheet(item: $likersTarget) { LikersView(post: $0) }
        .sheet(item: $shareItem) { item in ActivityShareSheet(items: [item.url]) }
        .sheet(isPresented: $showLogin) { CommunityLoginView() }
        .alert(String(localized: "community.report.done"), isPresented: $reportDone) {
            Button(String(localized: "common.done"), role: .cancel) {}
        }
    }
}
