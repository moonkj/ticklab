import SwiftUI

/// Round 133: 사진 소스 선택 (라이브러리/카메라/삭제) — iOS 표준 하단 시트.
/// confirmationDialog 가 iOS 26 에서 중앙 popover 로 렌더링되고 안의 PhotosPicker 가
/// trigger 안 되는 버그를 함께 우회.
/// Round (잔여 분할): WatchDetailView 의 private struct 에서 별 파일로 분리.
struct PhotoSourceSheet: View {
    var title: String
    var allowRemove: Bool
    /// Sprint 6 (P2-3): 보정 스타일 바인딩 — nil 이면 스타일 picker 표시 안 함.
    var processingStyle: Binding<ProcessingStyle>?
    var onLibrary: () -> Void
    var onCamera: () -> Void
    var onRemove: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var sheetHeight: CGFloat {
        var h: CGFloat = allowRemove ? 300 : 248
        if processingStyle != nil { h += 60 }
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            Capsule()
                .fill(AppColors.rule)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
            // 타이틀
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.ink2)
                .padding(.top, 16)
                .padding(.bottom, 8)
            // Sprint 6 (P2-3): 보정 스타일 picker
            if let style = processingStyle {
                Picker(String(localized: "photo.processing.style"), selection: style) {
                    Text(String(localized: "photo.processing.standard")).tag(ProcessingStyle.standard)
                    Text(String(localized: "photo.processing.caseback")).tag(ProcessingStyle.caseback)
                    Text(String(localized: "photo.processing.vivid")).tag(ProcessingStyle.vivid)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            Divider()
            // 액션 목록
            VStack(spacing: 0) {
                row(label: String(localized: "photo.source.library"), icon: "photo.on.rectangle", action: onLibrary)
                Divider().padding(.leading, 60)
                row(label: String(localized: "photo.source.camera"), icon: "camera", action: onCamera)
                if allowRemove, let onRemove {
                    Divider().padding(.leading, 60)
                    row(label: String(localized: "photo.source.remove"), icon: "trash", destructive: true, action: onRemove)
                }
            }
            // 취소 — 중립 색상 (accent 아님)
            Divider().padding(.top, 8)
            Button { dismiss() } label: {
                Text(String(localized: "common.cancel"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.plain)
        }
        .background(AppColors.paper1.ignoresSafeArea())
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppColors.paper1)
    }

    @ViewBuilder
    private func row(label: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ConceptGlyph(systemName: icon, size: 17)
                    .foregroundStyle(destructive ? AppColors.danger : AppColors.accent)
                    .frame(width: 28, alignment: .center)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.ink0)  // 삭제도 텍스트는 ink0 — 아이콘만 빨강
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
