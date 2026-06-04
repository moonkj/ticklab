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
    @State private var editTarget: Community.Post?
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
            .sheet(item: $editTarget) { post in
                CommunityEditView(post: post)
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
            .alert(String(localized: "community.warning.title"), isPresented: $showWarning) {
                Button(String(localized: "common.ok")) {
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
                String(localized: "community.admin.delete.confirm"),
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
            eyebrow: String(localized: "community.eyebrow"),
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
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(notifCount > 0 ? AppColors.accent : AppColors.ink0)
                    .symbolRenderingMode(notifCount > 0 ? .multicolor : .monochrome)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "collection.notifications"))
            Button { showSavedTab() } label: {
                Image(systemName: "bookmark").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.ink0).frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "community.saved.title"))
            Button { startCompose() } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22, weight: .regular))
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
                Image(systemName: "gearshape").font(.system(size: 22, weight: .regular))
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
            scopeTab(String(localized: "community.scope.all"), selected: !followingOnly) {
                withAnimation(.easeOut(duration: 0.15)) { followingOnly = false }
            }
            scopeTab(String(localized: "community.scope.following"), selected: followingOnly) {
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
                    Text(String(localized: "community.scope.following.empty"))
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
                            guard service.isSignedIn else { showLogin = true; return }   // 감사 수정: 미로그인 거짓 "신고 완료" 방지
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
                        onEdit: post.isMine(currentUID: service.myUID) ? { editTarget = post } : nil,
                        onAdminDelete: (actingAsTickLab && !post.isMine(currentUID: service.myUID)) ? { adminDeleteTarget = post } : nil
                    )
                    // 웨이브2-C: 하드 0.5px divider → 갤러리 여백(포스트 간 호흡 확대).
                    Color.clear.frame(height: 18)
                }
            }
            .padding(.top, 8)
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

