import SwiftUI

/// 풀스크린 사진 뷰어. Pinch zoom + double-tap + swipe-down dismiss.
struct FullscreenPhotoViewer: View {
    let imageData: Data?
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cachedImage: UIImage?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let uiImage = cachedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dragOffset)
                    .opacity(dragOffset == 0 ? 1 : max(0.4, 1 - Double(abs(dragOffset)) / 300))
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(5.0, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.05 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            scale = 1.0; lastScale = 1.0
                                            offset = .zero; lastOffset = .zero
                                        }
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.05 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    } else {
                                        dragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if scale <= 1.05 {
                                        if abs(dragOffset) > 80 {
                                            onDismiss()
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                dragOffset = 0
                                            }
                                        }
                                    } else {
                                        lastOffset = offset
                                    }
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if scale > 1.0 {
                                scale = 1.0; lastScale = 1.0
                                offset = .zero; lastOffset = .zero
                            } else {
                                scale = 2.5; lastScale = 2.5
                            }
                        }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // 닫기 버튼 — 상단 안전 영역 고려한 위치
            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.18))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .accessibilityLabel(String(localized: "common.close"))
                    Spacer()
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(id: imageData) {
            if let data = imageData {
                cachedImage = UIImage(data: data)
            } else {
                cachedImage = nil
            }
        }
    }
}

#Preview {
    FullscreenPhotoViewer(imageData: nil, onDismiss: {})
}
