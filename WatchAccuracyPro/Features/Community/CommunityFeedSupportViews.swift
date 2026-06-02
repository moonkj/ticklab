import SwiftUI
import UIKit

/// 저장(스크랩) 탭 — 북마크한 게시물 목록.
struct CommunitySavedView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared
    @State private var shareItem: ShareCardItem?
    @State private var loaded = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if !loaded && service.savedFeed.isEmpty {
                    ProgressView().tint(AppColors.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.savedFeed.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 44)).foregroundStyle(AppColors.ink3)
                        Text(String(localized: "community.saved.empty"))
                            .font(AppTypography.bodySmall).foregroundStyle(AppColors.ink2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(service.savedFeed) { post in
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
                                        Task { await service.report(post, reason: reason) }
                                    },
                                    onBlock: { Task { await service.block(authorOf: post) } },
                                    onFollow: { guard service.isSignedIn else { showLogin = true; return }; Task { await service.toggleFollow(post.authorUID) } },
                                    onBookmark: { guard service.isSignedIn else { showLogin = true; return }; Task { await service.toggleBookmark(post) } },
                                    onShare: {
                                        if let url = service.imageURL(for: post.imagePath) { shareItem = ShareCardItem(url: url) }
                                    },
                                    onDelete: nil
                                )
                                Rectangle().fill(AppColors.rule).frame(height: 0.5)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .background(AppColors.paper0)
            .navigationTitle(String(localized: "community.saved.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .task { await service.loadSavedPosts(); loaded = true }
            .sheet(item: $shareItem) { item in ActivityShareSheet(items: [item.url]) }
            .sheet(isPresented: $showLogin) { CommunityLoginView() }
        }
    }
}

/// 피드 카드 — 사진 + 좋아요 + 신고/차단 메뉴 + (게이팅) 흐림.
/// 앱 아이콘을 런타임 UIImage 로 — 커뮤니티 운영(TickLab) 계정 아바타용. 실패 시 nil → 글자 아바타 폴백.
enum AppIconProvider {
    static let image: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }()
}

