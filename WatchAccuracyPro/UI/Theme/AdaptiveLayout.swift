import SwiftUI

/// iPad(regular 가로폭)에서 콘텐츠를 읽기 좋은 최대폭으로 제한하고 가운데 정렬한다.
/// iPhone(compact)에서는 완전 no-op — 기존 레이아웃에 영향 없음.
/// 배경(paper0 등)은 바깥에서 full-bleed 유지하고, 본문만 폭을 제한하는 용도.
struct ReadableContentWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    var maxWidth: CGFloat

    func body(content: Content) -> some View {
        if hSize == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)   // 남는 좌우 공간에서 가운데 정렬
        } else {
            content
        }
    }
}

extension View {
    /// iPad 가로폭에서만 본문 최대폭 제한 + 가운데 정렬 (iPhone 무영향).
    func readableContentWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}
