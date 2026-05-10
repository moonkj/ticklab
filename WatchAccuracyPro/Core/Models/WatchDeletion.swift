import Foundation
import SwiftData

/// SwiftData iOS 17.x에서 `@Relationship(deleteRule: .cascade)` 가 명시적 `save()` 후
/// 자식을 cascade 하지 못하는 버그를 회피하기 위한 헬퍼.
/// 배포 타깃이 iOS 17 이므로 프로덕션 삭제 경로는 항상 이 헬퍼를 통과해야 한다.
extension Watch {
    func deleteCascade(in context: ModelContext) {
        for measurement in measurements {
            context.delete(measurement)
        }
        context.delete(self)
    }
}
