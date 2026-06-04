import SwiftUI

/// 럭셔리 카드 머티리얼 — 연속곡률 + paperSheen 채움 + 2겹 그림자 +
/// 상단 1px white inner-highlight(상단 모서리에 빛이 닿은 듯한 하이라이트).
///
/// 정적 머티리얼(애니메이션 없음). 60fps budget 무관.
/// 사용처: 결과/정적/빈상태 카드 머티리얼 격상.
struct LuxeCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var elevated: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(AppGradients.paperSheen))
            .overlay {
                // 상단 white inner-highlight — 1px stroke, 위→아래로 빠르게 사라짐.
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
            }
            .overlay {
                // hairline 외곽선 — 카드 경계를 또렷하게.
                shape.strokeBorder(AppColors.rule, lineWidth: 0.5)
            }
            .clipShape(shape)
            .cardShadow(elevated ? .high : .mid)
    }
}

extension View {
    /// 럭셔리 카드 머티리얼을 적용한다.
    /// - Parameters:
    ///   - cornerRadius: 연속곡률 반경(기본 16).
    ///   - elevated: 더 깊은 그림자(`.high`) 적용 여부.
    func luxeCard(cornerRadius: CGFloat = 16, elevated: Bool = false) -> some View {
        modifier(LuxeCardModifier(cornerRadius: cornerRadius, elevated: elevated))
    }
}

#Preview("LuxeCard") {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: "Luxe Card", number: "01")
            Text("Premium material")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.ink0)
            Text("paperSheen + 2겹 그림자 + 상단 하이라이트")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.ink2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxeCard()

        VStack(alignment: .leading, spacing: 8) {
            Text("Elevated")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.ink0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxeCard(cornerRadius: 24, elevated: true)
    }
    .padding(24)
    .background(AppColors.paper2)
}
