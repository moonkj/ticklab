import SwiftUI

/// Sprint 9 (UX): 스켈레톤 로딩 — shimmer 애니메이션.
/// ProgressView 대신 콘텐츠 형태를 유지하는 플레이스홀더.
struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    var cornerRadius: CGFloat = 8
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(shimmerGradient)
            .frame(height: height)
            .onAppear {
                // 접근성: Reduce Motion 켜진 경우 무한 shimmer 정지 (정적 플레이스홀더).
                guard !reduceMotion else { phase = 0.5; return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AppColors.paper2, location: phase - 0.3),
                .init(color: AppColors.paper1.opacity(0.6), location: phase),
                .init(color: AppColors.paper2, location: phase + 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// 시계 리스트 로딩 스켈레톤 행.
struct WatchListRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView(cornerRadius: 12, height: 76)
                .frame(width: 76)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(cornerRadius: 4, height: 12).frame(width: 60)
                SkeletonView(cornerRadius: 6, height: 18).frame(width: 140)
                SkeletonView(cornerRadius: 4, height: 12).frame(width: 80)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    VStack(spacing: 12) {
        WatchListRowSkeleton()
        WatchListRowSkeleton()
        WatchListRowSkeleton()
    }
    .padding()
    .background(AppColors.paper0)
}
