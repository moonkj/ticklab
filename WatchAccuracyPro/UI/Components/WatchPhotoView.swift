import SwiftUI

/// Data 기반 비동기 이미지 뷰 — PhotoCache + 백그라운드 디코딩.
struct WatchPhotoView<Placeholder: View>: View {
    let id: UUID
    let data: Data?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(id: UUID, data: Data?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.id = id; self.data = data; self.placeholder = placeholder
        // 캐시 hit 시 초기값 즉시 설정 (첫 생성 시 flash 방지). data nil 이면 캐시 조회 안 함.
        _image = State(initialValue: data == nil ? nil : PhotoCache.cache.object(forKey: id as NSUUID))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadImage() }
        // Sprint 11 (Min #1): data 전체(수 MB) Equatable 비교 대신 byte count 토큰으로 감시.
        // 같은 count 다른 이미지 케이스는 등록 경로에서 PhotoCache.invalidate가 처리하므로 안전.
        .onChange(of: data?.count) { _, _ in
            image = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let data else { image = nil; return }
        if image != nil { return }
        // 캐시 확인 — hit이면 즉시 표시
        if let cached = PhotoCache.cache.object(forKey: id as NSUUID) {
            image = cached; return
        }
        // 캐시 miss — 백그라운드 다운샘플 디코딩 (PhotoCache 와 동일 경로, nonisolated)
        let watchID = id
        Task.detached(priority: .userInitiated) {
            let decoded = PhotoCache.image(for: watchID, data: data)
            if let decoded { await MainActor.run { self.image = decoded } }
        }
    }
}
