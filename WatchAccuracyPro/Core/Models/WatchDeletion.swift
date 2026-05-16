import Foundation
import SwiftData
import UIKit

/// Round 145 (Sora #1, #7, #8): UIImage(data:) 매 body 재실행 방지.
/// SwiftData Watch.photoData 의 디코드 결과를 NSCache 에 보관해 list cell 재현 시 재사용.
/// 키: Watch.id (UUID). 메모리 압박 시 시스템이 자동 비움.
enum PhotoCache {
    private static let cache: NSCache<NSUUID, UIImage> = {
        let c = NSCache<NSUUID, UIImage>()
        // Round 14 (Sora): countLimit 64 → 32 + totalCostLimit 256MB.
        // 4032×3024 사진 UIImage 한 장 ~50MB → 64장이면 3.2GB 메모리 압박.
        c.countLimit = 32
        c.totalCostLimit = 256 * 1024 * 1024
        return c
    }()
    static func image(for id: UUID, data: Data?) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        // Round 21 (Sora): data.count = JPEG 압축 크기. NSCache 에 들어가는 건 decoded UIImage 라
        //   width × height × scale^2 × 4 bytes (RGBA) — 4MP 사진은 4MB JPEG → ~46MB decoded (11x).
        //   cost mismatch 면 totalCostLimit 256MB 가 실제론 ~12장 만에 fill → 500MB 점유 위험.
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Round (3-1): 사진 저장 직후 호출 — background thread 에서 미리 디코드 + 캐시 적재.
    /// 다음 ListRow/Hero display 시 cache hit → main thread 디코드 spike 회피.
    /// 호출처: AddWatchView save(), photo source sheet 사진 set 시.
    static func prefetch(for id: UUID, data: Data?) {
        guard let data else { return }
        let key = id as NSUUID
        // 이미 캐시되어 있으면 no-op.
        guard cache.object(forKey: key) == nil else { return }
        Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return }
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
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
        // 1) 측정들 삭제 — Round 14 (Hyemi): faulted SwiftData relationship 을 iteration 중 mutate 하는
        //    undefined behavior 회피를 위해 Array snapshot 후 delete.
        for measurement in Array(measurements) {
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
        // 7) Notification identifier 정리 — wind / battery / overhaul reminder.
        NotificationService.cancelWindReminder(for: self)
        NotificationService.cancelBatteryReminder(for: self)
        NotificationService.cancelOverhaulReminder(for: self)

        // 8) Watch 자체 삭제
        context.delete(self)
    }
}

extension Notification.Name {
    /// Round 139 (Min Critical): Watch 삭제 직전 notification — 사이드 listener (측정 cancel 등) 가
    ///   in-flight 작업을 정리할 기회 제공. (예전 LongTestRunner 언급은 phase 2 미구현 — TODO(phase2).)
    static let ticklabWatchWillDelete = Notification.Name("ticklab.watch.willDelete")
    /// Round 140 (H1): 측정 진행 중 RootTabView .id() reset 차단.
    static let ticklabMeasurementDidStart = Notification.Name("ticklab.measurement.didStart")
    static let ticklabMeasurementDidEnd = Notification.Name("ticklab.measurement.didEnd")
    /// Round 149 (Hyemi 7 H1): ProEntitlement.isPro 변경 시 — UserPreferences instance 동기화.
    static let ticklabProEntitlementChanged = Notification.Name("ticklab.pro.changed")
}

extension JournalEntry {
    /// Round 170: 일기 삭제 시 사진 파일도 cleanup.
    /// Round 24 (Sora): JournalPhotoCache 도 동시 invalidate — 동일 path 재사용 시 stale image 잔존 차단.
    func deleteWithFiles(in context: ModelContext) {
        let fm = FileManager.default
        for path in photoPaths {
            JournalPhotoCache.invalidate(path)
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        context.delete(self)
    }
}

extension Watch {
    /// Round 19 (Min): isPrimary invariant 보호 — 컬렉션 내 1개만 true (Hard Rule 9).
    ///   호출자가 직접 watch.isPrimary = true 만 set 하면 두 시계 다 true 가능.
    ///   이 헬퍼로 통일해 atomic guarantee.
    @discardableResult
    static func setPrimary(_ target: Watch, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Watch>(predicate: #Predicate { $0.isPrimary })
        guard let primaries = try? context.fetch(descriptor) else { return false }
        for w in primaries where w.id != target.id {
            w.isPrimary = false
        }
        target.isPrimary = true
        return (try? context.save()) != nil
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
