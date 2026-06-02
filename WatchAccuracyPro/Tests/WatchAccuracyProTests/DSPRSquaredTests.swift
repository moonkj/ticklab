import XCTest
@testable import WatchAccuracyPro

/// `DSPPipeline.coefficientOfDetermination` 회귀 보호 (감사 P0 수정).
/// 핵심: 인덱스는 OLS 와 동일한 sparse nominal-round 여야 한다. beat 누락(sparse) 구간에서
/// sequential 0..N-1 인덱스를 쓰면 R² 가 과소 계산돼 정상 OLS 가 median 으로 잘못 fallback 했다.
final class DSPRSquaredTests: XCTestCase {

    private let period = 0.125   // 28800 BPH nominal 주기

    private func beat(_ t: Double) -> BeatEvent { BeatEvent(timestampSeconds: t, type: .tic, energy: 1.0) }

    /// 연속 beat — 라인에 정확히 올라가면 R²≈1 (sparse/sequential 무관 동일).
    func test_consecutiveBeats_onLine_r2_is_one() {
        let beats = (0..<20).map { beat(Double($0) * period) }
        let r2 = DSPPipeline.coefficientOfDetermination(beats: beats, slope: period, nominalPeriod: period)
        XCTAssertEqual(r2, 1.0, accuracy: 1e-9)
    }

    /// 핵심 회귀: beat 누락(인덱스 3·7·12 빠짐)인데 데이터는 라인에 정확 → R²≈1 이어야.
    /// (기존 sequential 인덱싱 버그면 이 케이스에서 R² 가 1 보다 한참 작아 fallback 됐다.)
    func test_sparseBeats_onLine_r2_is_one_with_correct_indexing() {
        let presentIndices = [0, 1, 2, 4, 5, 6, 8, 9, 10, 11, 13, 14, 15]   // 3·7·12 누락
        let beats = presentIndices.map { beat(Double($0) * period) }
        let r2 = DSPPipeline.coefficientOfDetermination(beats: beats, slope: period, nominalPeriod: period)
        XCTAssertEqual(r2, 1.0, accuracy: 1e-9, "sparse 인덱스를 OLS 와 동일하게 써야 R²=1")
    }

    /// 노이즈가 큰 beat → R² 낮음(게이트가 fallback 시키도록).
    func test_noisyBeats_r2_below_threshold() {
        let jitter = [0.0, 0.02, -0.03, 0.04, -0.02, 0.03, -0.04, 0.02]
        let beats = jitter.enumerated().map { beat(Double($0.offset) * period + $0.element) }
        let r2 = DSPPipeline.coefficientOfDetermination(beats: beats, slope: period, nominalPeriod: period)
        XCTAssertLessThan(r2, 0.999)
    }

    func test_invalidInputs_returnZero() {
        XCTAssertEqual(DSPPipeline.coefficientOfDetermination(beats: [beat(0)], slope: period, nominalPeriod: period), 0)
        XCTAssertEqual(DSPPipeline.coefficientOfDetermination(beats: [beat(0), beat(period)], slope: period, nominalPeriod: 0), 0)
    }
}
