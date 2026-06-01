import SwiftUI
import UIKit

/// 커뮤니티 익명 사진 피드. 좋아요·신고·차단 + (게이팅 ON 시) 인기글 부분 흐림.
/// FeatureFlags.communityEnabled OFF 면 RootTabView 가 탭 자체를 노출 안 함.
struct CommunityFeedView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.purchaseRouter) private var purchaseRouter
    @StateObject private var service = CommunityService.shared
    @ObservedObject private var flags = FeatureFlags.shared

    @State private var showComposer = false
    @State private var showEULA = false
    @State private var showDailyLimit = false
    @State private var reportDone = false
    @State private var commentTarget: Community.Post?
    @State private var likersTarget: Community.Post?
    @State private var showViewerGate = false
    /// 신원 전환: 게시·좋아요 등 액션 전 Apple 로그인 게이트.
    @State private var showLogin = false
    /// 최초 피드 로드 완료 여부 — 로딩 중에 "게시물 없음"이 깜빡이는 것 방지.
    @State private var didInitialLoad = false
    /// 공유시트 + 저장(스크랩) 탭 + 계정/프로필.
    @State private var shareItem: ShareCardItem?
    @State private var showSaved = false
    @State private var showProfile = false
    @State private var showBlocked = false
    /// 활동 알림(좋아요·팔로워) — 종 배지. 컬렉션과 동일 소스(CommunityService).
    @State private var showNotifications = false
    @State private var notifCount = 0
    /// 운영 ID(관리자) 활성 — 모든 글 삭제 권한 노출.
    @AppStorage("ticklab.admin.actingAsTickLab") private var actingAsTickLab = false
    @State private var adminDeleteTarget: Community.Post?
    /// 피드 범위 — false=전체, true=팔로잉한 계정만.
    @State private var followingOnly = false
    /// 운영자 경고 — 내 미확인 경고.
    @State private var myWarnings: [Community.Warning] = []
    @State private var showWarning = false

    /// 부분 흐림 대상 인기 기준 (좋아요 수). 저품질 익명글 흐림 역효과 방지.
    private let popularThreshold = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorialHeader
                if service.hasAcceptedViewerTerms && !service.feed.isEmpty {
                    feedScopePicker
                }
                Group {
                    if !service.hasAcceptedViewerTerms {
                        viewerGate
                    } else if service.feed.isEmpty {
                        // 최초 로드 끝나기 전엔 로딩 표시 — "게시물 없음" 깜빡임 방지.
                        if didInitialLoad { emptyState } else { loadingState }
                    } else {
                        feedList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppColors.paper0)
            // 제목·버튼을 같은 최상단 영역으로 — 내비바 숨기고 에디토리얼 헤더에 버튼 오버레이.
            .toolbar(.hidden, for: .navigationBar)
            .task {
                // App Store 1.2: 뷰어도 약관 동의 후에만 UGC 노출 + 익명가입(Round 3 컴플라이언스).
                if service.hasAcceptedViewerTerms {
                    await service.loadFeed()
                    didInitialLoad = true
                    myWarnings = await service.fetchMyWarnings()
                    if !myWarnings.isEmpty { showWarning = true }
                    notifCount = await service.unseenNotificationCount()
                } else {
                    showViewerGate = true
                }
            }
            .refreshable { if service.hasAcceptedViewerTerms { await service.loadFeed() } }
            .sheet(isPresented: $showComposer) {
                CommunityComposerView()
            }
            .sheet(isPresented: $showLogin) {
                CommunityLoginView()
            }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showSaved) {
                CommunitySavedView()
            }
            .sheet(isPresented: $showProfile) {
                UserProfileView()
            }
            .sheet(isPresented: $showBlocked) {
                BlockedUsersView()
            }
            .sheet(item: $commentTarget) { post in
                CommentsView(post: post)
            }
            .sheet(item: $likersTarget) { post in
                LikersView(post: post)
            }
            .sheet(isPresented: $showNotifications) {
                CommunityNotificationsView()
            }
            .sheet(isPresented: $showEULA) {
                CommunityEULAView { service.acceptEULA(); showEULA = false; presentComposerIfAllowed() }
            }
            .fullScreenCover(isPresented: $showViewerGate) {
                CommunityEULAView {
                    service.acceptViewerTerms()
                    showViewerGate = false
                    Task { await service.loadFeed(); didInitialLoad = true }
                }
            }
            .alert(String(localized: "community.daily_limit.title"), isPresented: $showDailyLimit) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "community.daily_limit.body")) }
            .alert("운영자 경고", isPresented: $showWarning) {
                Button("확인") {
                    let ids = myWarnings.map { $0.id }
                    Task { await service.markWarningsSeen(ids) }
                }
            } message: {
                Text(myWarnings.map { $0.message }.joined(separator: "\n\n"))
            }
            .alert(String(localized: "community.report.done"), isPresented: $reportDone) {
                Button(String(localized: "common.done"), role: .cancel) {}
            }
            .confirmationDialog(
                "이 게시물을 삭제할까요? (관리자)",
                isPresented: Binding(get: { adminDeleteTarget != nil }, set: { if !$0 { adminDeleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    if let target = adminDeleteTarget { Task { await service.adminDeletePost(target) } }
                    adminDeleteTarget = nil
                }
                Button(String(localized: "common.cancel"), role: .cancel) { adminDeleteTarget = nil }
            }
        }
    }

    /// 에디토리얼 헤더 — 제목 + (우상단) 버튼들을 같은 최상단 영역에.
    private var editorialHeader: some View {
        EditorialPageHeader(
            eyebrow: "THE LOUNGE",
            title: String(localized: "community.tab.title"),
            subtitle: String(localized: "community.subtitle")
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .overlay(alignment: .topTrailing) {
            headerButtons.padding(.trailing, 12).padding(.top, 2)
        }
    }

    /// 우상단 버튼 — 저장됨 · 계정 · 작성. (제목과 같은 줄/영역)
    private var headerButtons: some View {
        HStack(spacing: 0) {
            Button { openNotifications() } label: {
                Image(systemName: notifCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 18))
                    .foregroundStyle(notifCount > 0 ? AppColors.accent : AppColors.ink0)
                    .symbolRenderingMode(notifCount > 0 ? .multicolor : .monochrome)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "collection.notifications"))
            Button { showSavedTab() } label: {
                Image(systemName: "bookmark").font(.system(size: 18))
                    .foregroundStyle(AppColors.ink0).frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "community.saved.title"))
            Button { startCompose() } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22))
                    .foregroundStyle(AppColors.ink0).frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "community.compose"))
            Menu {
                Button { showProfile = true } label: {
                    Label(String(localized: "community.menu.profile"), systemImage: "person.crop.circle")
                }
                Button { showBlocked = true } label: {
                    Label(String(localized: "community.blocked.manage"), systemImage: "hand.raised.slash")
                }
                if service.isSignedIn {
                    Button(role: .destructive) { service.signOut() } label: {
                        Label(String(localized: "community.menu.logout"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button { showLogin = true } label: {
                        Label(String(localized: "community.login.title"), systemImage: "person.crop.circle.badge.plus")
                    }
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 18))
                    .foregroundStyle(AppColors.ink0).frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "community.account"))
        }
    }

    /// 표시할 피드 — 팔로잉 모드면 팔로우한 작성자 글만.
    private var displayedFeed: [Community.Post] {
        followingOnly ? service.feed.filter { service.isFollowing($0.authorUID) } : service.feed
    }

    /// All / Following 밑줄 텍스트 탭 — 우측 정렬, 에디토리얼 톤(세그먼트보다 가볍게).
    private var feedScopePicker: some View {
        HStack(spacing: 20) {
            Spacer()
            scopeTab("All", selected: !followingOnly) {
                withAnimation(.easeOut(duration: 0.15)) { followingOnly = false }
            }
            scopeTab("Following", selected: followingOnly) {
                withAnimation(.easeOut(duration: 0.15)) { followingOnly = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func scopeTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? AppColors.ink0 : AppColors.ink3)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? AppColors.ink0 : .clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if followingOnly && displayedFeed.isEmpty {
                    Text("팔로우한 계정의 글이 아직 없어요.\n관심 있는 계정을 팔로우해 보세요.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
                ForEach(Array(displayedFeed.enumerated()), id: \.element.id) { index, post in
                    CommunityPostCard(
                        post: post,
                        liked: service.isLiked(post),
                        blurred: isBlurred(post, index: index),
                        following: service.isFollowing(post.authorUID),
                        bookmarked: service.isBookmarked(post),
                        isMine: post.isMine(currentUID: service.myUID),
                        onLike: {
                            guard service.isSignedIn else { showLogin = true; return }
                            Task { await service.toggleLike(post) }
                        },
                        onUnlock: { purchaseRouter?.intend(.community) },
                        onReport: { reason in
                            Task { await service.report(post, reason: reason); reportDone = true }
                        },
                        onBlock: { Task { await service.block(authorOf: post) } },
                        onFollow: {
                            guard service.isSignedIn else { showLogin = true; return }
                            Task { await service.toggleFollow(post.authorUID) }
                        },
                        onBookmark: {
                            guard service.isSignedIn else { showLogin = true; return }
                            Task { await service.toggleBookmark(post) }
                        },
                        onShare: { sharePost(post) },
                        onComment: { commentTarget = post },
                        onLikers: { likersTarget = post },
                        onDelete: post.isMine(currentUID: service.myUID) ? { Task { await service.deleteMyPost(post) } } : nil,
                        onAdminDelete: (actingAsTickLab && !post.isMine(currentUID: service.myUID)) ? { adminDeleteTarget = post } : nil
                    )
                    // 인스타 스타일 게시물 구분선.
                    Rectangle().fill(AppColors.rule).frame(height: 0.5)
                }
            }
            .padding(.top, 2)
        }
    }

    /// 뷰어 약관 게이트 — 동의 전엔 피드/익명가입 안 함(App Store 1.2).
    private var viewerGate: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.ink3)
            Text(String(localized: "community.eula.title"))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "community.eula.body"))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showViewerGate = true } label: {
                Text(String(localized: "community.eula.agree"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.paper0)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(AppColors.ink0)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 최초 로딩 — 빈 화면/깜빡임 대신 크고 분명한 로딩 스피너.
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(AppColors.ink1)
            Text(String(localized: "community.loading"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.ink3)
            Text(String(localized: "community.empty.title"))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "community.empty.body"))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
            Button { startCompose() } label: {
                Text(String(localized: "community.compose"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.paper0)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(AppColors.ink0)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gating

    private func isBlurred(_ post: Community.Post, index: Int) -> Bool {
        guard flags.communityGatingEnabled, !preferences.isPro else { return false }
        if post.isMine(currentUID: service.myUID) { return false }   // 본인 글 항상 노출
        guard index >= flags.communityFreeVisibleCount else { return false }  // 최근 N장 무료
        return post.likeCount >= popularThreshold                    // 인기글만 흐림
    }

    // MARK: - Compose flow

    private func startCompose() {
        guard service.isSignedIn else { showLogin = true; return }
        guard service.canPostToday else { showDailyLimit = true; return }
        if service.hasAcceptedEULA { showComposer = true } else { showEULA = true }
    }
    private func presentComposerIfAllowed() {
        if service.hasAcceptedEULA, service.canPostToday {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showComposer = true }
        }
    }
    private func sharePost(_ post: Community.Post) {
        guard let url = service.imageURL(for: post.imagePath) else { return }
        shareItem = ShareCardItem(url: url)
    }
    private func showSavedTab() {
        guard service.isSignedIn else { showLogin = true; return }
        showSaved = true
    }

    /// 종 탭 — 즉시 배지 클리어("확인하면 없어지고") + 알림 목록. 익명 세션도 본인 글 알림 표시.
    private func openNotifications() {
        service.markNotificationsSeen()
        notifCount = 0
        showNotifications = true
    }
}

/// 저장(스크랩) 탭 — 북마크한 게시물 목록.
struct CommunitySavedView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared
    @State private var shareItem: ShareCardItem?
    @State private var loaded = false

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
                                    onLike: { Task { await service.toggleLike(post) } },
                                    onUnlock: {},
                                    onReport: { _ in },
                                    onBlock: {},
                                    onFollow: { Task { await service.toggleFollow(post.authorUID) } },
                                    onBookmark: { Task { await service.toggleBookmark(post) } },
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

private struct CommunityPostCard: View {
    let post: Community.Post
    let liked: Bool
    let blurred: Bool
    let following: Bool
    let bookmarked: Bool
    let isMine: Bool
    let onLike: () -> Void
    let onUnlock: () -> Void
    let onReport: (Community.ReportReason) -> Void
    let onBlock: () -> Void
    let onFollow: () -> Void
    let onBookmark: () -> Void
    let onShare: () -> Void
    var onComment: () -> Void = {}
    var onLikers: () -> Void = {}
    let onDelete: (() -> Void)?
    /// 관리자(운영 ID) 전용 — 모든 글 삭제. nil 이면 미노출.
    var onAdminDelete: (() -> Void)? = nil

    // 코드리뷰: 카드는 service 를 관찰하면 안 됨(좋아요 1개에 전체 피드 re-render). imageURL 은
    //   순수 함수라 shared 에서 직접 호출 — 관찰 제거로 피드 성능 보호.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            imageView
                .aspectRatio(1.0, contentMode: .fit)   // 인스타 정사각, 풀폭(edge-to-edge)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay { if blurred { blurOverlay } }
            actions   // 좋아요·댓글 수는 아이콘 옆 인라인(actions 내부).
            if let caption = post.caption, !caption.isEmpty, !blurred {
                (Text(handle).font(.system(size: 13, weight: .semibold)).foregroundColor(AppColors.ink0)
                    + Text("  ")
                    + Text(caption).font(.system(size: 13)).foregroundColor(AppColors.ink1))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Subviews (인스타 스타일)

    /// 헤더 — 아바타 + 핸들(브랜드/익명) + 시간 + 더보기.
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                if post.authorName == "TickLab", let icon = AppIconProvider.image {
                    // 운영(TickLab) 계정 — 앱 아이콘 아바타로 고정.
                    Image(uiImage: icon).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Circle().fill(avatarColor)
                    if let path = post.authorAvatarPath, let url = CommunityService.shared.imageURL(for: path) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                            .clipShape(Circle())
                    } else {
                        Text(initial)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(handle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink3)
            }
            Spacer()
            // 팔로우 — 본인 글 제외.
            if !isMine {
                Button(action: onFollow) {
                    Text(String(localized: following ? "community.following" : "community.follow"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(following ? AppColors.ink2 : AppColors.paper0)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(following ? Color.clear : AppColors.ink0)
                        .overlay(Capsule().stroke(following ? AppColors.rule : Color.clear, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            moreMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var imageView: some View {
        if let url = CommunityService.shared.imageURL(for: post.imagePath) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure: missingImagePlaceholder   // 삭제·만료 등으로 사진 소실
                default: ZStack { Color(AppColors.paper2); ProgressView() }
                }
            }
        } else {
            missingImagePlaceholder
        }
    }

    /// 사진이 사라진(스토리지 소실·경로 없음) 게시물 — 빈 공백 대신 안내.
    private var missingImagePlaceholder: some View {
        ZStack {
            Color(AppColors.paper2)
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(AppColors.ink3)
                Text(String(localized: "community.image_unavailable"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink3)
            }
        }
    }

    /// 액션 줄 — 아이콘 옆 숫자(인스타식). 좋아요 수 탭 → 라이커, 댓글 아이콘/수 탭 → 댓글창.
    private var actions: some View {
        HStack(spacing: 18) {
            // 좋아요 — 하트 토글 + (탭 시 라이커) 숫자.
            HStack(spacing: 6) {
                Button(action: onLike) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 23))
                        .foregroundStyle(liked ? AppColors.danger : AppColors.ink0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "community.like"))
                if post.likeCount > 0 {
                    Button(action: onLikers) {
                        Text("\(post.likeCount)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.ink0)
                    }
                    .buttonStyle(.plain)
                }
            }
            // 댓글 — 아이콘 + 숫자, 탭 시 댓글창.
            Button(action: onComment) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right").font(.system(size: 21))
                    if let c = post.commentCount, c > 0 {
                        Text("\(c)").font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(AppColors.ink0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "community.comment.title"))
            Button(action: onShare) {
                Image(systemName: "paperplane")
                    .font(.system(size: 21))
                    .foregroundStyle(AppColors.ink0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "community.share"))
            Spacer()
            // 스크랩(저장).
            Button(action: onBookmark) {
                Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 21))
                    .foregroundStyle(bookmarked ? AppColors.accentDark : AppColors.ink0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "community.bookmark"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onShare) {
                Label(String(localized: "community.share"), systemImage: "square.and.arrow.up")
            }
            // 신고·차단은 타인 글에만 — 본인 글엔 자기신고/자기차단 무의미(자기차단은 피드 노출 버그까지).
            if !isMine {
                // 신고 — "..." 안에서 사유 하위 메뉴로 펼침(중앙 팝업 X, 글에 anchor).
                Menu {
                    ForEach(Community.ReportReason.allCases, id: \.self) { reason in
                        Button(role: .destructive) { onReport(reason) } label: {
                            Text(String(localized: String.LocalizationValue(reason.localizationKey)))
                        }
                    }
                } label: {
                    Label(String(localized: "community.report.title"), systemImage: "flag")
                }
                Button(role: .destructive, action: onBlock) {
                    Label(String(localized: "community.block"), systemImage: "hand.raised")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            }
            if let onAdminDelete {
                Button(role: .destructive, action: onAdminDelete) {
                    Label("관리자 삭제", systemImage: "trash.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.ink2)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(String(localized: "collection.more_menu"))
    }

    // MARK: - Derived

    /// 핸들 — 작성자 표시명 > 브랜드 태그 > (구 익명 글) 익명 라벨.
    private var handle: String {
        if let n = post.authorName, !n.isEmpty { return n }
        if let b = post.brand, !b.isEmpty { return b }
        return String(localized: "community.anon_handle")
    }
    /// 아바타 이니셜 — 핸들 첫 글자.
    private var initial: String {
        String(handle.first.map(String.init) ?? "?").uppercased()
    }
    private var timeAgo: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: post.createdAt, relativeTo: Date())
    }
    /// authorUID 기반 안정 해시 → 아바타 색. 익명은 유지하되 글마다 시각적 구분.
    private var avatarColor: Color {
        var h = 5381
        for byte in post.authorUID.utf8 { h = ((h << 5) &+ h) &+ Int(byte) }
        let hue = Double(abs(h) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }

    private var blurOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.25)
            Button(action: onUnlock) {
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 20))
                    Text(String(localized: "community.gate.cta"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 차단 관리 — 사용자가 차단한 작성자 목록 + 차단 해제.
/// 익명 커뮤니티라 닉네임이 없어 UID 끝 4자리로만 구분 표기(본인만 보는 본인 데이터).
private struct BlockedUsersView: View {
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

/// 커뮤니티 댓글 — 목록 + 작성(욕설·거래 필터) + 삭제(본인/운영자). 차단 작성자 댓글은 service가 제외.
private struct CommentsView: View {
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
            if ok { input = ""; focused = false; await reload() }
        }
    }

    private func delete(_ c: Community.Comment) async {
        comments.removeAll { $0.id == c.id }
        if !(await service.deleteComment(c.id)) { await reload() }
    }
}

/// 좋아요 라이커 목록(인스타 "누가 좋아요") — 이름 탭하면 그 사람 게시물, 옆에 팔로우 토글.
private struct LikersView: View {
    let post: Community.Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = CommunityService.shared
    @State private var likers: [Community.Liker] = []
    @State private var loaded = false

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
            .task { likers = await service.fetchLikers(postID: post.id); loaded = true }
        }
    }

    private func row(_ liker: Community.Liker) -> some View {
        let isMe = liker.uid == service.myUID
        let following = service.isFollowing(liker.uid)
        return HStack(spacing: 12) {
            // 이름·아바타 탭 → 그 사람 게시물.
            NavigationLink {
                UserPostsView(uid: liker.uid, displayName: liker.authorName)
            } label: {
                HStack(spacing: 12) {
                    LikerAvatar(name: liker.authorName).frame(width: 34, height: 34)
                    Text(liker.authorName ?? String(localized: "community.anon_handle"))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.ink0)
                }
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
private struct LikerAvatar: View {
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

/// 특정 사용자의 게시물 그리드(인스타 프로필 격자) + 팔로우. 익명 닉네임 표시.
private struct UserPostsView: View {
    let uid: String
    let displayName: String?
    @ObservedObject private var service = CommunityService.shared
    @State private var posts: [Community.Post] = []
    @State private var loaded = false

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
                        Button { Task { await service.toggleFollow(uid) } } label: {
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
                            AsyncImage(url: service.imageURL(for: p.imagePath)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Color(AppColors.paper2)
                                }
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        }
                    }
                }
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(displayName ?? String(localized: "community.anon_handle"))
        .navigationBarTitleDisplayMode(.inline)
        .task { posts = await service.fetchPostsByAuthor(uid: uid); loaded = true }
    }
}
