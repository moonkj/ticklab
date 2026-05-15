import XCTest
@testable import WatchAccuracyPro

final class DSPDownsampleTests: XCTestCase {
    func test_downsample_produces_target_length() {
        let chunk = (0..<4_800).map { Float(sin(Double($0) * 0.05)) }
        let out = DSPPipeline.downsample(chunk: chunk, target: 200)
        XCTAssertEqual(out.count, 200)
    }

    func test_downsample_normalizes_to_unit_range() {
        let chunk = (0..<1_000).map { _ in Float.random(in: -3...3) }
        let out = DSPPipeline.downsample(chunk: chunk, target: 100)
        XCTAssertLessThanOrEqual(out.max() ?? 0, 1.0001)
        XCTAssertGreaterThanOrEqual(out.min() ?? 0, 0) // peak-aware → 모든 값 ≥ 0 (abs)
    }

    func test_downsample_returns_empty_for_empty_input() {
        XCTAssertEqual(DSPPipeline.downsample(chunk: [], target: 200), [])
    }

    func test_downsample_returns_empty_for_zero_target() {
        XCTAssertEqual(DSPPipeline.downsample(chunk: [0.1, 0.2, 0.3], target: 0), [])
    }

    func test_downsample_short_input_passes_through_normalized() {
        let chunk: [Float] = [0.1, -0.5, 0.25]
        let out = DSPPipeline.downsample(chunk: chunk, target: 10)
        // chunk.count <= target → normalize 만 거침
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out.max() ?? 0, 0.5, accuracy: 0.001) // abs 가 아니라 sign 보존
        XCTAssertEqual(out.min() ?? 0, -1.0, accuracy: 0.001)
    }

    func test_downsample_preserves_peaks() {
        // 0이 대부분이고 한 군데 큰 spike → spike bin 만 1.0 이어야 함
        var chunk = [Float](repeating: 0, count: 1000)
        chunk[500] = 0.8
        let out = DSPPipeline.downsample(chunk: chunk, target: 10)
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(out.max() ?? 0, 1.0, accuracy: 0.001)
    }

    func test_downsample_handles_all_zeros_without_division() {
        let chunk = [Float](repeating: 0, count: 200)
        let out = DSPPipeline.downsample(chunk: chunk, target: 50)
        XCTAssertEqual(out.count, 50)
        XCTAssertTrue(out.allSatisfy { $0 == 0 })
    }
}
