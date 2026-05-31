import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// 발견성(R6): 시계를 iOS Spotlight 에 색인 — 브랜드·모델·캘리버·ref·별명으로 검색 → 탭 시 상세.
/// on-device, 외부 전송 0(Hard Rule #8 무충돌). 색인 식별자 = watch.id (딥링크에 사용).
enum WatchSpotlightIndexer {
    static let domain = "com.ticklab.watches"

    static func index(_ watches: [Watch]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items: [CSSearchableItem] = watches.map { w in
            let attr = CSSearchableItemAttributeSet(contentType: .text)
            attr.title = "\(w.brand) \(w.model)"
            var keywords = [w.brand, w.model]
            if let c = w.caliber, c != Watch.manualCaliberTag, !c.isEmpty { keywords.append(c) }
            if let ref = w.referenceNumber, !ref.isEmpty { keywords.append(ref) }
            if let nick = w.nickname, !nick.isEmpty { keywords.append(nick) }
            attr.keywords = keywords.filter { !$0.isEmpty }
            let desc = [
                (w.caliber == Watch.manualCaliberTag ? nil : w.caliber),
                w.referenceNumber
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            attr.contentDescription = desc.isEmpty ? nil : desc
            return CSSearchableItem(uniqueIdentifier: w.id.uuidString,
                                    domainIdentifier: domain,
                                    attributeSet: attr)
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func deindex(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString]) { _ in }
    }
}
