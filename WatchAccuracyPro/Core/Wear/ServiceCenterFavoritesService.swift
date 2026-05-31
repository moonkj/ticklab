import Foundation

/// Sprint 3 (P2-11): 워치메이커/서비스센터 즐겨찾기.
/// 별도 @Model 없이 UserDefaults 문자열 배열로 관리 — 스키마 마이그레이션 불필요.
/// 최대 20개 저장. 가장 최근 사용 순 정렬.
enum ServiceCenterFavoritesService {
    private static let key = "ticklab.serviceCenterFavorites"
    private static let maxCount = 20

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// 사용 시점 호출 — 최상위로 이동 (LRU 방식).
    static func recordUsage(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = all.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ name: String) {
        var list = all
        list.removeAll { $0 == name }
        UserDefaults.standard.set(list, forKey: key)
    }
}
