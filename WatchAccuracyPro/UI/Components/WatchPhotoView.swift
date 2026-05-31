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
        // init에서 캐시 hit 시 즉시 이미지 설정 — task 실행 전 flash 방지
        _image = State(initialValue: PhotoCache.cache.object(forKey: id as NSUUID))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else {
                placeholder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: data) {
            guard let data else {
                await MainActor.run { image = nil }
                return
            }
            // 이미 이미지가 있으면 (캐시 hit 또는 이전 로드) 재로드 안 함
            if image != nil { return }
            // 캐시 확인
            if let cached = PhotoCache.cache.object(forKey: id as NSUUID) {
                await MainActor.run { image = cached }
                return
            }
            // 백그라운드 디코딩
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let decoded, !Task.isCancelled else { return }
            let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
            PhotoCache.cache.setObject(decoded, forKey: id as NSUUID, cost: cost)
            await MainActor.run { image = decoded }
        }
        // 사진 교체 시(data 변경) 기존 이미지 클리어
        .onChange(of: data) { _, newData in
            if newData == nil { image = nil }
            else { image = nil }  // 새 data → task(id: data)가 재실행하므로 nil 처리
        }
    }
}
