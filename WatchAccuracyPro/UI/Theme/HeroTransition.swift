import SwiftUI

/// 공유요소(히어로) zoom 전환 헬퍼 — 목록 카드 → 상세로 갈 때 소스 뷰가 자연스럽게 확대.
/// iOS 18+ 의 `matchedTransitionSource` / `navigationTransition(.zoom)` 을 사용하고,
/// iOS 17 에선 no-op(기본 push) 으로 안전하게 폴백한다. (앱 최소 지원 iOS 17.0)
extension View {
    /// 전환의 **소스**(목록 카드 등)에 부착. `id` 는 목적지의 `heroDestination(id:)` 와 같은 값이어야 매칭된다.
    @ViewBuilder
    func heroSource(id: some Hashable, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
    }

    /// 전환의 **목적지**(상세 화면)에 부착. 같은 `id`/`namespace` 의 소스에서 zoom 으로 확대 전환된다.
    @ViewBuilder
    func heroDestination(id: some Hashable, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}
