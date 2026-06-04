import SwiftUI

/// 크롭 시트 present 용 래퍼 — UIImage 는 Identifiable 이 아니므로 fullScreenCover(item:) 에 사용.
struct CropImagePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 사진 업로드 크롭/프레이밍 — 표시 종횡비(기본 4:3)에 맞춰 사용자가 시계를 직접 맞춤.
/// 사용자 보고: 카드/상세가 scaledToFill center-crop 이라 시계가 잘려 보임 →
///   업로드(라이브러리·카메라) 시 "보이는 범위"를 직접 드래그·확대로 조정.
/// WYSIWYG: 화면에 보이는 크롭 영역을 그대로 ImageRenderer 로 렌더 → 표시와 저장 결과 일치.
struct PhotoCropView: View {
    let image: UIImage
    /// 크롭 프레임 종횡비 (width / height). 히어로 카드·상세 표시와 맞춤.
    var aspect: CGFloat = 4.0 / 3.0
    let onComplete: (Data) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var upright: UIImage?
    /// 크롭 프레임 크기 — export 가 컨트롤(GeometryReader 밖)에서 접근하려고 저장.
    @State private var cropSize: CGSize = .zero

    private let maxScale: CGFloat = 5

    /// 활성 윈도우의 안전영역 인셋 — 중첩 fullScreenCover에서 geo.safeAreaInsets가 0을 반환하는
    /// 문제를 회피하기 위해 윈도우에서 직접 읽는다(상태바/노치/Dynamic Island 확실 회피).
    private var safeInsets: UIEdgeInsets {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets)
            ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 크롭 이미지 레이어 — 풀스크린(세이프에어리어 무시), 중앙 정렬. 드래그·핀치.
            GeometryReader { geo in
                let cropW = geo.size.width
                let cropH = cropW / aspect
                let img = upright ?? image
                cropContent(img: img, cropW: cropW, cropH: cropH)
                    .frame(width: cropW, height: cropH)
                    .clipped()
                    .overlay(Rectangle().stroke(.white.opacity(0.85), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(dragGesture(img: img, cropW: cropW, cropH: cropH))
                    .simultaneousGesture(magnifyGesture(img: img, cropW: cropW, cropH: cropH))
                    .frame(width: geo.size.width, height: geo.size.height)  // 풀스크린 중앙
                    .onAppear {
                        cropSize = CGSize(width: cropW, height: cropH)
                        if upright == nil { upright = image.uprightCopy() }
                    }
            }
            .ignoresSafeArea()

            // 컨트롤 레이어 — ZStack 직속 자식이라 **세이프에어리어 준수**(상태바·노치 아래). 버튼 클릭 보장.
            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        Text(String(localized: "common.cancel"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button { exportCurrent() } label: {
                        Text(String(localized: "common.done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, safeInsets.top + 8)   // 윈도우 실제 상단 인셋 + 여유 → 상태바/노치 확실 회피
                .padding(.bottom, 12)
                .background(
                    LinearGradient(colors: [.black.opacity(0.55), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                Spacer()
                Text(String(localized: "photo.crop.hint"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .padding(.bottom, safeInsets.bottom + 20)
            }
        }
        .ignoresSafeArea()
    }

    /// 컨트롤(GeometryReader 밖)에서 호출 — 저장된 cropSize 로 export.
    @MainActor
    private func exportCurrent() {
        let img = upright ?? image
        // iPad split view 에서 UIScreen.main 은 전체화면 폭을 줘 어긋남 → 현재 윈도우 폭으로.
        let fallbackW = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.bounds.width ?? 390
        let w = cropSize.width > 0 ? cropSize.width : fallbackW
        export(img: img, cropW: w, cropH: w / aspect)
    }

    @ViewBuilder
    private func cropContent(img: UIImage, cropW: CGFloat, cropH: CGFloat) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: cropW, height: cropH)
            .scaleEffect(scale)
            .offset(offset)
    }

    // MARK: - Fill geometry

    /// scaledToFill 된 콘텐츠 크기 (scale 적용 전).
    private func filledSize(img: UIImage, cropW: CGFloat, cropH: CGFloat) -> CGSize {
        let imgAspect = img.size.width / max(img.size.height, 1)
        if imgAspect > aspect {
            return CGSize(width: cropH * imgAspect, height: cropH)
        } else {
            return CGSize(width: cropW, height: cropW / max(imgAspect, 0.01))
        }
    }

    private func clampedOffset(_ proposed: CGSize, img: UIImage, cropW: CGFloat, cropH: CGFloat) -> CGSize {
        let filled = filledSize(img: img, cropW: cropW, cropH: cropH)
        let sW = filled.width * scale
        let sH = filled.height * scale
        let maxX = max(0, (sW - cropW) / 2)
        let maxY = max(0, (sH - cropH) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    // MARK: - Gestures

    private func dragGesture(img: UIImage, cropW: CGFloat, cropH: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, img: img, cropW: cropW, cropH: cropH)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func magnifyGesture(img: UIImage, cropW: CGFloat, cropH: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(maxScale, max(1, baseScale * value))
                offset = clampedOffset(offset, img: img, cropW: cropW, cropH: cropH)
            }
            .onEnded { _ in
                baseScale = scale
                baseOffset = offset
            }
    }

    // MARK: - Export (WYSIWYG)

    @MainActor
    private func export(img: UIImage, cropW: CGFloat, cropH: CGFloat) {
        let content = cropContent(img: img, cropW: cropW, cropH: cropH)
            .frame(width: cropW, height: cropH)
            .clipShape(Rectangle())
        let renderer = ImageRenderer(content: content)
        // 출력 해상도: 약 1080px 폭 (PhotoCache 가 1024px 로 다운샘플하므로 충분).
        renderer.scale = max(1, 1080 / cropW)
        renderer.isOpaque = true
        if let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.9) {
            onComplete(data)
        } else {
            // 렌더 실패 시 원본 fallback.
            onComplete(img.jpegData(compressionQuality: 0.9) ?? Data())
        }
    }
}

extension UIImage {
    /// EXIF orientation 을 픽셀에 굽어 .up 으로 정규화 — ImageRenderer/크롭 좌표 일치 보장.
    func uprightCopy() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#Preview {
    PhotoCropView(
        image: UIImage(systemName: "applewatch") ?? UIImage(),
        onComplete: { _ in },
        onCancel: {}
    )
}
