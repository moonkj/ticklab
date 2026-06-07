import SwiftUI

/// 페이지 상단 editorial 헤더 — eyebrow (mono uppercase) + serif italic title + 부제.
/// Collection/Journal/Stats/Today 모두 이 컴포넌트 사용 (시각 일관성).
struct EditorialPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    /// 브랜드 시그니처 — eyebrow 옆 앰비언트 틱톡 기어(1초 1스텝). 홈에서만 권장.
    var showGear: Bool = false
    /// 제목 옆 애니메이션 탭 아이콘(나타날 때 시그니처 모션 1회). 폰트 절반 크기.
    var titleIcon: RootTabView.Tab? = nil

    init(eyebrow: String, title: String, subtitle: String? = nil,
         showGear: Bool = false, titleIcon: RootTabView.Tab? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.showGear = showGear
        self.titleIcon = titleIcon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if showGear {
                    TickingGearView(teeth: 10, size: 13, color: AppColors.accent)
                }
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.accent)
            }
            HStack(alignment: .center, spacing: 9) {
                Text(title)
                    .font(.system(size: 38, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(AppColors.ink0)
                if let titleIcon {
                    HeaderTabIcon(kind: titleIcon, size: 19, color: AppColors.accent)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    EditorialPageHeader(
        eyebrow: "TICKLAB",
        title: "Collection",
        subtitle: "Your wrist, your time"
    )
    .padding(20)
    .background(AppColors.paper0)
}
