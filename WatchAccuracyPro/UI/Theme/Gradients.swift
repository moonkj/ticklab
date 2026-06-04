import SwiftUI

/// 럭셔리 표면(골드/페이퍼)을 위한 정적 그라데이션 토큰.
/// - 전부 `let`/`var`(정적 계산) — 매 프레임 비용 없음. 애니메이션 무관.
/// - AppColors 의 accent 계열을 재사용해 브랜드 일관성을 유지한다.
enum AppGradients {
    // MARK: - Gold foil (광택 골드 사선 — 카드/인장/배지 채움)
    /// 좌상 → 우하로 흐르는 골드 포일. 밝은→중간→어두운→중간→밝은 5스톱으로
    /// "금박이 빛에 따라 번지는" 새틴 광택을 흉내낸다.
    static let goldFoil = LinearGradient(
        stops: [
            .init(color: AppColors.accentLight, location: 0.00),
            .init(color: AppColors.accent,      location: 0.30),
            .init(color: AppColors.accentDark,  location: 0.52),
            .init(color: AppColors.accent,      location: 0.74),
            .init(color: AppColors.accentLight, location: 1.00),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Gold brushed (미세 새틴 — 원형 인장/링 채움)
    /// 중심을 도는 앵귤러 골드. 헤어라인 결을 흉내내는 미세 새틴.
    /// DotRingMark·GoldSealView 의 골드 톤 채움에 사용.
    static let goldBrushed = AngularGradient(
        stops: [
            .init(color: AppColors.accentLight, location: 0.00),
            .init(color: AppColors.accent,      location: 0.18),
            .init(color: AppColors.accentDark,  location: 0.42),
            .init(color: AppColors.accent,      location: 0.62),
            .init(color: AppColors.accentLight, location: 0.82),
            .init(color: AppColors.accentLight, location: 1.00),
        ],
        center: .center
    )

    // MARK: - Paper sheen (페이퍼 톤 미세 광택 — luxeCard 머티리얼 채움)
    /// paper1(상단, 밝음) → paper0(하단, 살짝 따뜻함). 카드 표면에 미세한 결을 준다.
    static let paperSheen = LinearGradient(
        colors: [AppColors.paper1, AppColors.paper0],
        startPoint: .top,
        endPoint: .bottom
    )
}

#Preview("Gradients") {
    VStack(spacing: 16) {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppGradients.goldFoil)
            .frame(height: 80)
            .overlay(Text("goldFoil").font(.caption).foregroundStyle(.white))

        Circle()
            .fill(AppGradients.goldBrushed)
            .frame(width: 100, height: 100)
            .overlay(Text("goldBrushed").font(.caption2).foregroundStyle(.white))

        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppGradients.paperSheen)
            .frame(height: 80)
            .overlay(Text("paperSheen").font(.caption).foregroundStyle(AppColors.ink2))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.rule, lineWidth: 1))
    }
    .padding()
    .background(AppColors.paper2)
}
