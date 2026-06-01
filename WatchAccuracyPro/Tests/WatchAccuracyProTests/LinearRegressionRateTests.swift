import XCTest
@testable import WatchAccuracyPro

/// PURE math 커버리지: LinearRegressionRate — beat index vs timestamp 의 LSQ regression.
final class LinearRegressionRateTests: XCTestCase {

    /// 정확히 `ioi` 초 간격의 N개 beat 를 만든다 (완벽한 직선 → r² = 1).
    private func evenBeats(count: Int, ioi: Double, start: Double = 0) -> [BeatEvent] {
        (0..<count).map {
            BeatEvent(timestampSeconds: start + Double($0) * ioi,
                      type: $0.isMultiple(of: 2) ? .tic : .toc,
                      energy: 1)
        }
    }

    // MARK: - slopeSecondsPerBeat

    func test_slope_perfectLine_matchesIOI_and_rSquaredOne() {
        let ioi = 0.125  // 28800 BPH → 0.125 s/beat
        let beats = evenBeats(count: 240, ioi: ioi)
        let result = LinearRegressionRate.slopeSecondsPerBeat(beats: beats)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope, ioi, accuracy: 1e-9)
        XCTAssertEqual(result!.rSquared, 1.0, accuracy: 1e-9)
    }

    func test_slope_returnsNil_belowMinimumBeats() {
        // guard beats.count >= 4
        XCTAssertNil(LinearRegressionRate.slopeSecondsPerBeat(beats: evenBeats(count: 3, ioi: 0.1)))
        XCTAssertNil(LinearRegressionRate.slopeSecondsPerBeat(beats: []))
    }

    func test_slope_returnsNil_whenAllTimestampsIdentical() {
        // denY == 0 (y 분산 없음) → nil
        let beats = (0..<10).map { _ in BeatEvent(timestampSeconds: 5.0, type: .tic, energy: 1) }
        XCTAssertNil(LinearRegressionRate.slopeSecondsPerBeat(beats: beats))
    }

    func test_slope_robustToSmallNoise() {
        // 작은 zig-zag noise 가 있어도 slope 는 평균 IOI 근처, r² 는 높게 유지.
        let ioi = 0.1
        var beats: [BeatEvent] = []
        for i in 0..<100 {
            let jitter = (i.isMultiple(of: 2) ? 1.0 : -1.0) * 0.0005
            beats.append(BeatEvent(timestampSeconds: Double(i) * ioi + jitter,
                                   type: .tic, energy: 1))
        }
        let result = LinearRegressionRate.slopeSecondsPerBeat(beats: beats)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope, ioi, accuracy: 1e-3)
        XCTAssertGreaterThan(result!.rSquared, 0.99)
    }

    // MARK: - bph

    func test_bph_perfectLine_28800() {
        let beats = evenBeats(count: 240, ioi: 0.125)  // 3600 / 0.125 = 28800
        let bph = LinearRegressionRate.bph(beats: beats)
        XCTAssertNotNil(bph)
        XCTAssertEqual(bph!, 28_800, accuracy: 1e-3)
    }

    func test_bph_21600() {
        let ioi = 3_600.0 / 21_600.0
        let beats = evenBeats(count: 200, ioi: ioi)
        let bph = LinearRegressionRate.bph(beats: beats)
        XCTAssertNotNil(bph)
        XCTAssertEqual(bph!, 21_600, accuracy: 1e-2)
    }

    func test_bph_nil_whenInsufficientBeats() {
        XCTAssertNil(LinearRegressionRate.bph(beats: evenBeats(count: 2, ioi: 0.1)))
    }

    // MARK: - secondsPerDay

    func test_secondsPerDay_zeroWhenMatchingNominal() {
        // measured BPH == nominal → rate 0
        let beats = evenBeats(count: 240, ioi: 0.125)
        let rate = LinearRegressionRate.secondsPerDay(beats: beats, nominalBph: 28_800)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 0, accuracy: 0.5)
    }

    func test_secondsPerDay_positiveWhenRunningFast() {
        // 약간 빠른(IOI 작은) 시계 → 양수 rate.
        let fastIOI = 0.125 * (1 - 0.0001)   // 0.01% 빠름 → ~+8.6 s/d
        let beats = evenBeats(count: 400, ioi: fastIOI)
        let rate = LinearRegressionRate.secondsPerDay(beats: beats, nominalBph: 28_800)
        XCTAssertNotNil(rate)
        XCTAssertGreaterThan(rate!, 0)
    }

    func test_secondsPerDay_nil_whenNominalNonPositive() {
        let beats = evenBeats(count: 240, ioi: 0.125)
        XCTAssertNil(LinearRegressionRate.secondsPerDay(beats: beats, nominalBph: 0))
        XCTAssertNil(LinearRegressionRate.secondsPerDay(beats: beats, nominalBph: -1))
    }

    func test_secondsPerDay_nil_whenInsufficientBeats() {
        XCTAssertNil(LinearRegressionRate.secondsPerDay(beats: evenBeats(count: 1, ioi: 0.1),
                                                        nominalBph: 28_800))
    }
}
