import SwiftUI
import UIKit

/// 브랜드 태그 칩 — 커뮤니티 카드 brandChip 과 동일 스타일(태그 아이콘 + 브랜드명, info 파랑 캡슐).
struct BrandTagChip: View {
    let brand: String
    var body: some View {
        HStack(spacing: 4) {
            ConceptGlyph(systemName: "tag.fill", size: 11)
            Text(brand).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(AppColors.info)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(Capsule().stroke(AppColors.info.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
    }
}

/// 특정 사용자의 게시물 그리드(인스타 프로필 격자) + 팔로우. 익명 닉네임 표시.
struct UserPostsView: View {
    let uid: String
    let displayName: String?
    @ObservedObject private var service = CommunityService.shared
    @State private var posts: [Community.Post] = []
    @State private var loaded = false
    @State private var showLogin = false
    @State private var followers = 0
    @State private var following = 0
    @State private var showEditProfile = false

    private let cols = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    LikerAvatar(name: displayName, avatarPath: posts.first?.authorAvatarPath).frame(width: 56, height: 56)
                    Text(displayName ?? String(localized: "community.anon_handle"))
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(AppColors.ink0)
                    Spacer()
                    if uid != service.myUID {
                        let isFollowing = service.isFollowing(uid)
                        Button {
                            guard service.isSignedIn else { showLogin = true; return }   // 감사 수정: 미로그인 조용한 팔로우 실패 방지
                            Task { await service.toggleFollow(uid) }
                        } label: {
                            Text(String(localized: isFollowing ? "community.following" : "community.follow"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isFollowing ? AppColors.ink2 : AppColors.paper0)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(isFollowing ? Color.clear : AppColors.ink0)
                                .overlay(Capsule().stroke(isFollowing ? AppColors.rule : Color.clear, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 내 프로필 — 편집 버튼.
                        Button { showEditProfile = true } label: {
                            Text(String(localized: "community.profile.edit", defaultValue: "프로필 편집"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)

                // 인스타식 통계 — 게시물 / 팔로워 / 팔로잉.
                HStack(spacing: 0) {
                    statCell(count: posts.count, title: String(localized: "community.stat.posts", defaultValue: "게시물"))
                    statCell(count: followers, title: String(localized: "community.stat.followers", defaultValue: "팔로워"))
                    statCell(count: following, title: String(localized: "community.stat.following", defaultValue: "팔로잉"))
                }
                .padding(.horizontal, 16)

                // 컬렉터 정보 — 소개 + 시작연도·좋아하는 브랜드·대표 메이커. (서버 비정규화 스냅샷, 욕설 필터 통과분)
                if let info = posts.first,
                   [info.authorBio, info.authorStartYear, info.authorFavBrands, info.authorRepBrand].contains(where: { $0?.isEmpty == false }) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let bio = info.authorBio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            let line = collectorLine(info)
                            if !line.isEmpty {
                                Text(line)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.ink3)
                            }
                            // 대표 메이커 — 커뮤니티 카드와 동일한 브랜드 태그 칩으로.
                            if let rep = info.authorRepBrand, !rep.isEmpty {
                                BrandTagChip(brand: rep)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }

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
                                                    ConceptGlyph(systemName: "text.alignleft", size: 11)
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
        .sheet(isPresented: $showEditProfile) { UserProfileView() }
        .task {
            posts = await service.fetchPostsByAuthor(uid: uid); loaded = true
            let c = await service.fetchProfileCounts(uid: uid)
            followers = c.followers; following = c.following
        }
    }

    /// 인스타식 통계 셀 — 큰 숫자 + 라벨.
    private func statCell(count: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.ink0)
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    /// 컬렉터 정보 한 줄 — 시작연도 · 좋아하는 브랜드 · 대표 메이커.
    private func collectorLine(_ p: Community.Post) -> String {
        var parts: [String] = []
        if let y = p.authorStartYear, !y.isEmpty {
            parts.append(String(format: String(localized: "profile.since"), y))
        }
        if let b = p.authorFavBrands, !b.isEmpty { parts.append(b) }
        // 대표 메이커는 텍스트가 아니라 BrandTagChip 으로 별도 표시.
        return parts.joined(separator: " · ")
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
