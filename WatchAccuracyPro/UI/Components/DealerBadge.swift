import SwiftUI

/// 프로필 헤더의 "딜러" 인증 배지 — 버튼처럼 입체감을 준 골드 칩.
///
/// 평면 캡슐 텍스트 대신 ⓐ 골드 포일 그라데이션 ⓑ 인증 seal 아이콘
/// ⓒ 상단 inner highlight(광택) ⓓ 골드 그림자로 "눌리는 버튼" 질감을 낸다.
/// 실제 탭 동작은 상위 프로필 행 버튼이 가지므로 시각적 버튼(비대화형)이다.
struct DealerBadge: View {
    /// 크기 변형 — 헤더(.small) / 강조(.regular).
    enum Size { case small, regular }
    var size: Size = .small

    private var fontSize: CGFloat { size == .small ? 10 : 12 }
    private var iconSize: CGFloat { size == .small ? 9 : 11 }
    private var hPad: CGFloat { size == .small ? 8 : 10 }
    private var vPad: CGFloat { size == .small ? 3 : 5 }

    var body: some View {
        HStack(spacing: 3) {
            DealerSealIcon(size: iconSize + 2, color: AppColors.primaryDeep)
            Text(String(localized: "profile.badge.dealer"))
                .font(.system(size: fontSize, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundStyle(AppColors.primaryDeep)
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(
            Capsule().fill(AppGradients.goldFoil)
        )
        .overlay(
            // 상단 흰 inner highlight → 볼록한 버튼 광택.
            Capsule().stroke(
                LinearGradient(
                    colors: [.white.opacity(0.6), .white.opacity(0.05), .clear],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        )
        .shadow(color: AppColors.accent.opacity(0.45), radius: 2.5, x: 0, y: 1.5)
        .accessibilityLabel(Text(String(localized: "profile.badge.dealer")))
    }
}

#Preview("Dealer badge") {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            Text("하늘").font(.system(size: 16, weight: .semibold))
            DealerBadge()
        }
        DealerBadge(size: .regular)
    }
    .padding(40)
    .background(AppColors.paper1)
}
