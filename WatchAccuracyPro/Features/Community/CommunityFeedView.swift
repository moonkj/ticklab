import SwiftUI

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
    @State private var reportTarget: Community.Post?
    @State private var showViewerGate = false

    /// 부분 흐림 대상 인기 기준 (좋아요 수). 저품질 익명글 흐림 역효과 방지.
    private let popularThreshold = 3

    var body: some View {
        NavigationStack {
            Group {
                if !service.hasAcceptedViewerTerms {
                    viewerGate
                } else if service.feed.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .background(AppColors.paper0)
            .navigationTitle(String(localized: "community.tab.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startCompose() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColors.ink0)
                    }
                    .accessibilityLabel(String(localized: "community.compose"))
                }
            }
            .task {
                // App Store 1.2: 뷰어도 약관 동의 후에만 UGC 노출 + 익명가입(Round 3 컴플라이언스).
                if service.hasAcceptedViewerTerms { await service.loadFeed() } else { showViewerGate = true }
            }
            .refreshable { if service.hasAcceptedViewerTerms { await service.loadFeed() } }
            .sheet(isPresented: $showComposer) {
                CommunityComposerView()
            }
            .sheet(isPresented: $showEULA) {
                CommunityEULAView { service.acceptEULA(); showEULA = false; presentComposerIfAllowed() }
            }
            .fullScreenCover(isPresented: $showViewerGate) {
                CommunityEULAView {
                    service.acceptViewerTerms()
                    showViewerGate = false
                    Task { await service.loadFeed() }
                }
            }
            .alert(String(localized: "community.daily_limit.title"), isPresented: $showDailyLimit) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(String(localized: "community.daily_limit.body")) }
            .confirmationDialog(
                String(localized: "community.report.title"),
                isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }),
                titleVisibility: .visible
            ) {
                if let target = reportTarget {
                    ForEach(Community.ReportReason.allCases, id: \.self) { reason in
                        Button(String(localized: String.LocalizationValue(reason.localizationKey)), role: .destructive) {
                            Task { await service.report(target, reason: reason) }
                            reportTarget = nil
                        }
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) { reportTarget = nil }
                }
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(service.feed.enumerated()), id: \.element.id) { index, post in
                    CommunityPostCard(
                        post: post,
                        liked: service.isLiked(post),
                        blurred: isBlurred(post, index: index),
                        onLike: { Task { await service.toggleLike(post) } },
                        onUnlock: { purchaseRouter?.intend(.community) },
                        onReport: { reportTarget = post },
                        onBlock: { Task { await service.block(authorOf: post) } },
                        onDelete: post.isMine(currentUID: service.myUID) ? { Task { await service.deleteMyPost(post) } } : nil
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
        guard service.canPostToday else { showDailyLimit = true; return }
        if service.hasAcceptedEULA { showComposer = true } else { showEULA = true }
    }
    private func presentComposerIfAllowed() {
        if service.hasAcceptedEULA, service.canPostToday {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showComposer = true }
        }
    }
}

/// 피드 카드 — 사진 + 좋아요 + 신고/차단 메뉴 + (게이팅) 흐림.
private struct CommunityPostCard: View {
    let post: Community.Post
    let liked: Bool
    let blurred: Bool
    let onLike: () -> Void
    let onUnlock: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: (() -> Void)?

    // 코드리뷰: 카드는 service 를 관찰하면 안 됨(좋아요 1개에 전체 피드 re-render). imageURL 은
    //   순수 함수라 shared 에서 직접 호출 — 관찰 제거로 피드 성능 보호.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = CommunityService.shared.imageURL(for: post.imagePath) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Color(AppColors.paper2)
                        default: ZStack { Color(AppColors.paper2); ProgressView() }
                        }
                    }
                } else {
                    Color(AppColors.paper2)
                }
            }
            .aspectRatio(1.0, contentMode: .fit)   // 인스타 스타일 정사각(1:1)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { if blurred { blurOverlay } }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? AppColors.danger : AppColors.ink2)
                        Text("\(post.likeCount)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.ink2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "community.like"))
                Spacer()
                if let brand = post.brand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(AppTypography.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(AppColors.ink3)
                }
                Menu {
                    Button(role: .destructive, action: onReport) {
                        Label(String(localized: "community.report.title"), systemImage: "flag")
                    }
                    Button(role: .destructive, action: onBlock) {
                        Label(String(localized: "community.block"), systemImage: "hand.raised")
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.ink3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(String(localized: "collection.more_menu"))
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
        }
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
