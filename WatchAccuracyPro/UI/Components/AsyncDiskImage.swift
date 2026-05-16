import SwiftUI

/// Round 15 (Doyoon/Jay/Sora 합의): JournalFeedView 가 grid/feed body 안에서
/// `Data(contentsOf:) + UIImage(data:)` 를 동기 호출하던 패턴을 캐시 + 비동기 로드로 교체.
/// 같은 path 가 다시 요청되면 NSCache 히트 → 즉시 동기 반환.
/// 캐시 미스면 placeholder 후 detached task 로 디코드 + 캐시 적재.
enum JournalPhotoCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // 썸네일 위주이므로 count 우선. 4032×3024 풀해상도 적재 막기 위해 cost 도 적용.
        c.countLimit = 96
        c.totalCostLimit = 128 * 1024 * 1024
        return c
    }()
    static func cached(_ path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }
    static func set(_ image: UIImage, cost: Int, forPath path: String) {
        cache.setObject(image, forKey: path as NSString, cost: cost)
    }
    static func invalidate(_ path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}

/// 디스크 사진을 NSCache + Task 로 비동기 로드. body 안에서 안전.
struct AsyncDiskImage<Placeholder: View>: View {
    let storedPath: String
    let resolve: (String) -> String?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        storedPath: String,
        resolve: @escaping (String) -> String? = { EXIFStripper.resolvePhotoPath($0) },
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.storedPath = storedPath
        self.resolve = resolve
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: storedPath) {
            if let cached = JournalPhotoCache.cached(storedPath) {
                image = cached
                return
            }
            let resolveFn = resolve
            let path = storedPath
            let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let resolved = resolveFn(path) else { return nil }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved)),
                      let img = UIImage(data: data) else { return nil }
                // Round 20 (Sora): JPEG 압축 크기(data.count) ≠ decoded UIImage 메모리.
                //   4MP JPEG ~4MB 가 디코드되면 ~50MB 차지 → totalCostLimit 128MB 가 무력화됨.
                //   실제 메모리 추정: width × height × scale^2 × 4 bytes (RGBA).
                let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
                JournalPhotoCache.set(img, cost: cost, forPath: path)
                return img
            }.value
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}
