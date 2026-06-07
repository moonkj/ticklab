import SwiftUI
import SwiftData
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
    // 내 컬렉션(온디바이스) — 내 프로필 탭에서만 사용. 남의 컬렉션은 서버에 없어 표시 불가(Hard Rule #8).
    @Query(sort: \Watch.createdAt, order: .reverse) private var myWatches: [Watch]
    @State private var tab: ProfileTab = .posts
    private enum ProfileTab { case posts, collection }
    private var isMe: Bool { uid == service.myUID }
    private let collCols = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileCard
                if isMe {
                    signatureSection
                    activitySection
                    tabBar
                }
                tabContent
            }
            .padding(.bottom, 24)
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

    // MARK: - 프로필 카드 (골드바 + 헤더 + 통계 + 액션 + 컬렉터 정보 + 내 시계 통계)

    private var profileCard: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [AppColors.accentLight, AppColors.accent, AppColors.accentDark],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    LikerAvatar(name: displayName, avatarPath: posts.first?.authorAvatarPath)
                        .frame(width: 60, height: 60)
                        .overlay(Circle().stroke(AppColors.accent, lineWidth: 2.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName ?? String(localized: "community.anon_handle"))
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(AppColors.ink0)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let since = sinceText {
                            Text(since)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppColors.accentDark)
                        }
                    }
                    Spacer(minLength: 8)
                    actionButton
                }
                HStack(spacing: 0) {
                    statCell(count: posts.count, title: String(localized: "community.stat.posts", defaultValue: "게시물"))
                    statCell(count: followers, title: String(localized: "community.stat.followers", defaultValue: "팔로워"))
                    statCell(count: following, title: String(localized: "community.stat.following", defaultValue: "팔로잉"))
                }
                collectorInfo
                if isMe { watchStatsStrip }
            }
            .padding(18)
        }
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppColors.rule, lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var sinceText: String? {
        guard let y = posts.first?.authorStartYear, !y.isEmpty else { return nil }
        return String(format: String(localized: "profile.since"), y)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isMe {
            Button { showEditProfile = true } label: {
                Text(String(localized: "community.profile.edit", defaultValue: "프로필 편집"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.ink0)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
            }.buttonStyle(.plain)
        } else {
            let isFollowing = service.isFollowing(uid)
            Button {
                guard service.isSignedIn else { showLogin = true; return }
                Task { await service.toggleFollow(uid) }
            } label: {
                Text(String(localized: isFollowing ? "community.following" : "community.follow"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFollowing ? AppColors.interactiveTint : AppColors.paper0)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(isFollowing ? Color.clear : AppColors.interactiveTint)
                    .overlay(Capsule().stroke(isFollowing ? AppColors.interactiveTint : Color.clear, lineWidth: 1.5))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var collectorInfo: some View {
        if let info = posts.first,
           [info.authorBio, info.authorFavBrands, info.authorRepBrand].contains(where: { $0?.isEmpty == false }) {
            VStack(alignment: .leading, spacing: 8) {
                if let bio = info.authorBio, !bio.isEmpty {
                    Text(bio).font(.system(size: 13)).foregroundStyle(AppColors.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let fav = info.authorFavBrands, !fav.isEmpty {
                        Text(fav).font(.system(size: 12)).foregroundStyle(AppColors.ink3)
                    }
                    if let rep = info.authorRepBrand, !rep.isEmpty { BrandTagChip(brand: rep) }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 내 시계 통계 (온디바이스)

    private var watchStatsStrip: some View {
        let measCount = myWatches.reduce(0) { $0 + $1.measurements.count }
        let latestRates = myWatches.compactMap { $0.measurements.max(by: { $0.timestamp < $1.timestamp })?.rateSecondsPerDay }
        let avgAcc = latestRates.isEmpty ? 0 : latestRates.map { abs($0) }.reduce(0, +) / Double(latestRates.count)
        return HStack(spacing: 0) {
            wStat(num: "\(myWatches.count)", label: String(localized: "community.wstat.watches", defaultValue: "보유 시계"))
            Divider().frame(height: 30).overlay(AppColors.accent.opacity(0.18))
            wStat(num: "\(measCount)", label: String(localized: "community.wstat.measures", defaultValue: "총 측정"))
            Divider().frame(height: 30).overlay(AppColors.accent.opacity(0.18))
            wStat(num: "±\(String(format: "%.1f", avgAcc))", unit: "s/d",
                  label: String(localized: "community.wstat.accuracy", defaultValue: "평균 정확도"))
        }
        .padding(.vertical, 13).padding(.horizontal, 8)
        .background(AppColors.accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func wStat(num: String, unit: String? = nil, label: String) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(num).font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(AppColors.ink0)
                if let unit { Text(unit).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppColors.accentDark) }
            }
            Text(label).font(.system(size: 10.5)).foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 탭 (게시물 / 컬렉션)

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.posts, icon: "square.grid.2x2", title: "\(String(localized: "community.stat.posts", defaultValue: "게시물")) \(posts.count)")
            tabButton(.collection, icon: "circle.grid.2x2", title: "\(String(localized: "tab.collection")) \(myWatches.count)")
        }
        .padding(4)
        .background(AppColors.paper2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func tabButton(_ t: ProfileTab, icon: String, title: String) -> some View {
        let on = tab == t
        let fg = on ? AppColors.accentDark : AppColors.ink3
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
            HStack(spacing: 6) {
                ConceptGlyph(systemName: icon, size: 15, color: fg)
                Text(title).font(.system(size: 13, weight: on ? .bold : .medium))
                    .foregroundStyle(fg)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            // 선택 탭 — 흰색 pill + 그림자 + 골드 글자로 배경(paper2)과 또렷이 구분.
            .background(on ? AppColors.paper0 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? AppColors.accent.opacity(0.35) : Color.clear, lineWidth: 1))
            .shadow(color: on ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isMe && tab == .collection {
            collectionGrid
        } else {
            postsGrid
        }
    }

    @ViewBuilder
    private var postsGrid: some View {
        if loaded && posts.isEmpty {
            Text(String(localized: "community.user.empty"))
                .font(.system(size: 14)).foregroundStyle(AppColors.ink3)
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(posts) { p in
                    NavigationLink { PostDetailView(post: p) } label: { postTile(p) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func postTile(_ p: Community.Post) -> some View {
        Color(AppColors.paper2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if p.imagePath == nil {
                    Text(p.caption ?? "")
                        .font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                        .lineLimit(4).multilineTextAlignment(.leading).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: .bottomTrailing) {
                            ConceptGlyph(systemName: "text.alignleft", size: 11)
                                .foregroundStyle(AppColors.ink3).padding(6)
                        }
                } else {
                    AsyncImage(url: service.imageURL(for: p.imagePath)) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() } else { Color.clear }
                    }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var collectionGrid: some View {
        if myWatches.isEmpty {
            Text(String(localized: "collection.empty.title", defaultValue: "아직 등록된 시계가 없어요"))
                .font(.system(size: 14)).foregroundStyle(AppColors.ink3)
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            LazyVGrid(columns: collCols, spacing: 11) {
                ForEach(myWatches) { w in collectionCard(w) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func collectionCard(_ w: Watch) -> some View {
        let latest = w.measurements.max(by: { $0.timestamp < $1.timestamp })
        let rate = latest?.rateSecondsPerDay
        let rateColor: Color = {
            guard let r = rate else { return AppColors.ink3 }
            let a = abs(r); return a <= 6 ? AppColors.success : a <= 20 ? AppColors.warning : AppColors.danger
        }()
        return VStack(alignment: .leading, spacing: 9) {
            HStack { Spacer(); WatchSilhouette(watch: w, size: 64); Spacer() }
            Text(w.brand).font(.system(size: 13, weight: .bold)).foregroundStyle(AppColors.ink0).lineLimit(1)
            Text(w.model).font(.system(size: 10, design: .monospaced)).foregroundStyle(AppColors.ink3).lineLimit(1)
            Divider()
            HStack {
                if let r = rate {
                    Text("\(r >= 0 ? "+" : "")\(String(format: "%.1f", r)) s/d")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(rateColor)
                } else {
                    Text("—").font(.system(size: 13, design: .monospaced)).foregroundStyle(AppColors.ink3)
                }
                Spacer()
                Text(String(format: String(localized: "community.wcard.measures", defaultValue: "측정 %d회"), w.measurements.count))
                    .font(.system(size: 10)).foregroundStyle(AppColors.ink3)
            }
        }
        .padding(13)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 대표 시계 / 측정 활동 (내 프로필 · 온디바이스)

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2).foregroundStyle(AppColors.accentDark)
            Rectangle().fill(AppColors.accent.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var signatureSection: some View {
        if let w = myWatches.first(where: { $0.isPrimary }) ?? myWatches.first {
            let latest = w.measurements.max(by: { $0.timestamp < $1.timestamp })
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(String(localized: "community.section.signature", defaultValue: "대표 시계"))
                HStack(spacing: 16) {
                    WatchSilhouette(watch: w, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(w.brand + " " + w.model)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(AppColors.ink0).lineLimit(2)
                        if let ref = w.referenceNumber, !ref.isEmpty {
                            Text(ref).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppColors.ink3)
                        }
                        if let m = latest {
                            HStack(spacing: 10) {
                                Text("\(m.rateSecondsPerDay >= 0 ? "+" : "")\(String(format: "%.1f", m.rateSecondsPerDay)) s/d")
                                    .font(.system(size: 18, weight: .medium, design: .serif))
                                    .foregroundStyle(rateColor(m.rateSecondsPerDay))
                                gradePill(m.confidenceScore)
                            }
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
        }
    }

    private func rateColor(_ r: Double) -> Color {
        let a = abs(r); return a <= 6 ? AppColors.success : a <= 20 ? AppColors.warning : AppColors.danger
    }

    private func gradePill(_ score: Int) -> some View {
        let g = score >= 80 ? "A" : score >= 60 ? "B" : "C"
        return HStack(spacing: 4) {
            Text(g).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Circle().fill(AppColors.accent))
            Text(String(localized: "community.signature.reliability", defaultValue: "신뢰도"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(AppColors.accentDark)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AppColors.accent.opacity(0.12)).clipShape(Capsule())
    }

    @ViewBuilder
    private var activitySection: some View {
        let timestamps = myWatches.flatMap { $0.measurements.map(\.timestamp) }
        if !timestamps.isEmpty {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let counts: [Date: Int] = timestamps.reduce(into: [:]) { $0[cal.startOfDay(for: $1), default: 0] += 1 }
            let streak = StreakService.streak(from: timestamps).current
            let total = (0..<70).reduce(0) { acc, i in
                let d = cal.date(byAdding: .day, value: -(69 - i), to: today)!
                return acc + (counts[d, default: 0] > 0 ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(String(localized: "community.section.activity", defaultValue: "측정 활동"))
                VStack(spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            ConceptGlyph(systemName: "flame.fill", size: 16, color: AppColors.accent)
                            Text(String(format: String(localized: "community.activity.streak", defaultValue: "%d일 연속 측정"), streak))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.ink0)
                        }
                        Spacer()
                        Text(String(format: String(localized: "community.activity.total", defaultValue: "최근 10주 · %d회"), total))
                            .font(.system(size: 11)).foregroundStyle(AppColors.ink3)
                    }
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(13), spacing: 3), count: 7), spacing: 3) {
                        ForEach(0..<70, id: \.self) { i in
                            let d = cal.date(byAdding: .day, value: -(69 - i), to: today)!
                            heatCell(counts[d, default: 0])
                        }
                    }
                    .frame(height: 7 * 13 + 6 * 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
        }
    }

    private func heatCell(_ count: Int) -> some View {
        let color: Color = count == 0 ? AppColors.paper2
            : count == 1 ? AppColors.accent.opacity(0.35)
            : count == 2 ? AppColors.accent.opacity(0.65)
            : AppColors.accent
        return RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 13, height: 13)
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
