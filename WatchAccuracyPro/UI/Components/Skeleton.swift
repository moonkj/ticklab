import SwiftUI

/// Shimmer — 스켈레톤 위를 쓸고 지나가는 그라데이션. Reduce Motion 시 정적(은은한 톤만).
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, AppColors.paper0.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: phase * w * 1.6)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
        .clipped()
    }
}

extension View {
    /// 스켈레톤 placeholder 에 shimmer 스윕을 입힌다.
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

/// 스켈레톤 블록 — 콘텐츠가 들어올 자리의 회색 라운드 사각형(+shimmer).
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppColors.paper2)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .shimmering()
    }
}

/// 영상 카드 모양 스켈레톤 — 16:9 썸네일 + 제목 2줄 + 메타.
struct VideoCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.paper2)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .shimmering()
            SkeletonBlock(height: 15)
            SkeletonBlock(width: 200, height: 15)
            SkeletonBlock(width: 130, height: 11)
        }
        .accessibilityHidden(true)
    }
}

/// 일반 리스트 행 스켈레톤 — 아바타 원 + 2줄 텍스트(뉴스/커뮤니티 등).
struct ListRowSkeleton: View {
    var lines: Int = 2
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(AppColors.paper2).frame(width: 40, height: 40).shimmering()
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 14)
                SkeletonBlock(width: 220, height: 12)
                if lines >= 3 { SkeletonBlock(width: 150, height: 12) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            VideoCardSkeleton()
            ListRowSkeleton(lines: 3)
            ListRowSkeleton()
        }
        .padding()
    }
    .background(AppColors.paper0)
}
