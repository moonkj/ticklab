import SwiftUI
import UIKit

struct CommunityPostCard: View {
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
            if post.imagePath != nil {
                // 사진 글 — 정사각 이미지.
                imageView
                    .aspectRatio(1.0, contentMode: .fit)   // 인스타 정사각, 풀폭(edge-to-edge)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay { if blurred { blurOverlay } }
            } else {
                // Round 171 글-전용 글 — 이미지 없이 본문을 텍스트 카드로.
                textOnlyBody
            }
            actions   // 좋아요·댓글 수는 아이콘 옆 인라인(actions 내부).
            // 사진 글의 캡션은 액션 아래 인라인(글-전용은 textOnlyBody 가 본문 표시).
            if post.imagePath != nil, let caption = post.caption, !caption.isEmpty, !blurred {
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
            // Round 174 (사용자 요청): 아바타 하단에 대표 시계 메이커 칩(참고 디자인의 '주주' 위치).
            .overlay(alignment: .bottom) {
                if let rep = post.authorRepBrand, !rep.isEmpty {
                    Text(rep)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(AppColors.info)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.paper0, lineWidth: 1.5))
                        .fixedSize()
                        .offset(y: 7)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(handle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                        .lineLimit(1)
                    // Round 174 (사용자 요청): 이모지 대신 획득 뱃지 '이름'을 칩으로 표시.
                    if let badge = post.authorBadge, let name = BadgeCatalog.name(forBadge: badge) {
                        Text(name)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColors.accentDark)
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(AppColors.accent50)
                            .clipShape(Capsule())
                    }
                }
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

    /// Round 171 글-전용 게시 본문 — 이미지 없이 캡션을 카드로 표시.
    private var textOnlyBody: some View {
        Text(post.caption ?? "")
            .font(.system(size: 16))
            .foregroundColor(AppColors.ink0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.paper1)
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
                    Label(String(localized: "community.admin.delete"), systemImage: "trash.slash")
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

