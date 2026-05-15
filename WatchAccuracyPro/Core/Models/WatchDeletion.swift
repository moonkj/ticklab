import Foundation
import SwiftData
import UIKit

/// Round 145 (Sora #1, #7, #8): UIImage(data:) 매 body 재실행 방지.
/// SwiftData Watch.photoData 의 디코드 결과를 NSCache 에 보관해 list cell 재현 시 재사용.
/// 키: Watch.id (UUID). 메모리 압박 시 시스템이 자동 비움.
enum PhotoCache {
    private static let cache: NSCache<NSUUID, UIImage> = {
        let c = NSCache<NSUUID, UIImage>()
        c.countLimit = 64
        return c
    }()
    static func image(for id: UUID, data: Data?) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
    static func invalidate(id: UUID) { cache.removeObject(forKey: id as NSUUID) }
}

/// SwiftData iOS 17.x에서 `@Relationship(deleteRule: .cascade)` 가 명시적 `save()` 후
/// 자식을 cascade 하지 못하는 버그를 회피하기 위한 헬퍼.
/// 배포 타깃이 iOS 17 이므로 프로덕션 삭제 경로는 항상 이 헬퍼를 통과해야 한다.
extension Watch {
    /// Watch 와 그 자식(WatchMeasurement) 모두 삭제.
    func deleteCascade(in context: ModelContext) {
        NotificationCenter.default.post(name: .ticklabWatchWillDelete, object: nil, userInfo: ["watchId": self.id])
        // Round 147 (Min C1): PhotoCache eviction — 동일 UUID 재사용 시 stale 방지.
        PhotoCache.invalidate(id: self.id)
        // 1) 측정들 삭제
        for measurement in measurements {
            context.delete(measurement)
        }
        let watchID = self.id
        // 3) Round 166: SpecCard 의 audio / photo 파일도 disk 에서 정리.
        //    SwiftData cascade 만으로는 file system 의 m4a / jpg orphan.
        let specDescriptor = FetchDescriptor<SpecCard>(
            predicate: #Predicate { $0.watch?.id == watchID }
        )
        if let cards = try? context.fetch(specDescriptor) {
            let fm = FileManager.default
            for card in cards {
                if let p = card.audioPath, fm.fileExists(atPath: p) {
                    try? fm.removeItem(atPath: p)
                }
                if let p = card.photoPath, fm.fileExists(atPath: p) {
                    try? fm.removeItem(atPath: p)
                }
                context.delete(card)
            }
        }
        // 4) WearLog 도 cascade.
        let wearDescriptor = FetchDescriptor<WearLog>(
            predicate: #Predicate { $0.watch?.id == watchID }
        )
        if let logs = try? context.fetch(wearDescriptor) {
            for log in logs { context.delete(log) }
        }
        // 5) ServiceLog 도 cascade. (H-1: receiptPath 파일도 disk 에서 정리)
        let serviceDescriptor = FetchDescriptor<ServiceLog>(
            predicate: #Predicate { $0.watch?.id == watchID }
        )
        if let logs = try? context.fetch(serviceDescriptor) {
            let fm = FileManager.default
            for log in logs {
                if let p = log.receiptPath, fm.fileExists(atPath: p) {
                    try? fm.removeItem(atPath: p)
                }
                context.delete(log)
            }
        }
        // 6) Cycle5 데이터무결성 C-1/C-3: JournalEntry cascade + 사진 파일 정리.
        //    JournalEntry.watch 는 optional 이라 cascade 자동 X → 수동 정리 필수.
        let journalDescriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.watch?.id == watchID }
        )
        if let entries = try? context.fetch(journalDescriptor) {
            for entry in entries {
                entry.deleteWithFiles(in: context)
            }
        }
        // 7) Notification identifier 정리 — wind / battery reminder.
        NotificationService.cancelWindReminder(for: self)
        NotificationService.cancelBatteryReminder(for: self)

        // 8) Watch 자체 삭제
        context.delete(self)
    }
}

extension Notification.Name {
    /// Round 139 (Min Critical): Watch 삭제 직전 notification — LongTestRunner cancel 등 사이드 정리.
    static let ticklabWatchWillDelete = Notification.Name("ticklab.watch.willDelete")
    /// Round 140 (H1): 측정 진행 중 RootTabView .id() reset 차단.
    static let ticklabMeasurementDidStart = Notification.Name("ticklab.measurement.didStart")
    static let ticklabMeasurementDidEnd = Notification.Name("ticklab.measurement.didEnd")
    /// Round 149 (Hyemi 7 H1): ProEntitlement.isPro 변경 시 — UserPreferences instance 동기화.
    static let ticklabProEntitlementChanged = Notification.Name("ticklab.pro.changed")
}

extension JournalEntry {
    /// Round 170: 일기 삭제 시 사진 파일도 cleanup.
    func deleteWithFiles(in context: ModelContext) {
        let fm = FileManager.default
        for path in photoPaths where fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
        context.delete(self)
    }
}

extension WatchMeasurement {
    /// 측정 단독 삭제 — JournalEntry 의 stale reference 정리.
    func deleteWithJournalCleanup(in context: ModelContext) {
        let myMeasurementID = self.id
        let journalDescriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.measurementId == myMeasurementID }
        )
        if let entries = (try? context.fetch(journalDescriptor)) {
            for entry in entries { entry.measurementId = nil }
        }
        context.delete(self)
    }
}
