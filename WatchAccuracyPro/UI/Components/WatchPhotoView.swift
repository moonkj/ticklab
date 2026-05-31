import SwiftUI

/// Data 기반 비동기 이미지 뷰 — PhotoCache miss 시 백그라운드 디코딩 후 @State 갱신.
/// WatchListRow, Hero 등 watch.photoData 직접 사용 부분에 적용.
struct WatchPhotoView<Placeholder: View>: View {
    let id: UUID
    let data: Data?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        id: UUID,
        data: Data?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.id = id
        self.data = data
        self.contentMode = contentMode
        self.placeholder = placeholder
        // 캐시에 있으면 즉시 표시
        _image = State(initialValue: PhotoCache.image(for: id, data: nil) == nil
            ? nil
            : PhotoCache.image(for: id, data: data))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else {
                placeholder()
            }
        }
        .task(id: id) {
            guard image == nil, let data else { return }
            // 캐시 재확인 (다른 뷰가 prefetch 했을 수 있음)
            if let cached = PhotoCache.image(for: id, data: data) {
                image = cached
                return
            }
            // 백그라운드 디코딩
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let decoded else { return }
            let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
            PhotoCache.cache.setObject(decoded, forKey: id as NSUUID, cost: cost)
            await MainActor.run { image = decoded }
        }
    }
}
