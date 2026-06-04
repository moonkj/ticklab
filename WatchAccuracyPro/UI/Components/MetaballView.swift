import SwiftUI

/// 웨이브2-A: gooey "메타볼" 합성 헬퍼.
///
/// 여러 둥근 형태(노브 + 이동 잔상)를 하나의 점성 액체처럼 융합시킨다.
/// 기법: 자식 뷰들을 `compositingGroup` 으로 묶어 한 레이어로 만든 뒤
///   `.blur(blurRadius)` → `.contrast(contrast)` 를 적용하면, blur 로 번진 알파의
///   가장자리가 high-contrast 에서 임계값처럼 잘려 두 형태가 만나는 지점이
///   매끄럽게 연결된(gooey) 실루엣이 된다.
///
/// 비용: 셰이더 없이 순수 SwiftUI 합성. 토글 전환(0.3s) 동안만 활성 — 측정 라이브
///   화면 16ms budget 과 무관.
///
/// Reduce Motion 등으로 gooey 효과를 끄고 싶을 땐 호출부에서 `MetaballView` 대신
///   자식을 그대로 그리면 된다(이 뷰는 효과 적용 책임만 진다).
struct MetaballView<Content: View>: View {
    /// blur 반경. 클수록 형태가 더 멀리서도 융합되지만 가장자리가 흐려진다.
    var blurRadius: CGFloat = 8
    /// 대비 배율. 클수록 blur 가장자리가 날카롭게 잘려 액체 표면이 또렷해진다.
    var contrast: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .compositingGroup()
            .blur(radius: blurRadius)
            .contrast(contrast)
            // contrast 가 색을 과포화시키므로, 호출부는 보통 단색(흰색/골드) 노브에 적용하고
            // 색은 바깥 트랙/오버레이에서 입힌다.
            .compositingGroup()
    }
}

#Preview("Metaball merge") {
    ZStack {
        Color.black
        MetaballView(blurRadius: 10, contrast: 22) {
            ZStack {
                Circle().fill(.white).frame(width: 60, height: 60).offset(x: -22)
                Circle().fill(.white).frame(width: 60, height: 60).offset(x: 22)
                Capsule().fill(.white).frame(width: 70, height: 40)
            }
        }
    }
    .ignoresSafeArea()
}
