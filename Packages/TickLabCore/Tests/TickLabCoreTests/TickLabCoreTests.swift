import XCTest
@testable import TickLabCore

final class TickLabCoreTests: XCTestCase {
    func test_version() {
        XCTAssertFalse(TickLabCoreVersion.current.isEmpty)
    }
}
