import SwiftUI

struct PrimaryButton: View {
    enum Style { case filled, bordered }
    let title: String
    let style: Style
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String, style: Style = .filled, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style == .bordered ? AppColors.primary : .clear, lineWidth: 1.5)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }

    private var background: Color {
        switch style {
        case .filled: return AppColors.primary
        case .bordered: return .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .filled: return .white
        case .bordered: return AppColors.primary
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton("저장하기") {}
        PrimaryButton("취소", style: .bordered) {}
        PrimaryButton("비활성", isEnabled: false) {}
    }
    .padding()
}
