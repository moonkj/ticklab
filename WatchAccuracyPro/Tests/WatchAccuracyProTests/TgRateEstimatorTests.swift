import XCTest
@testable import WatchAccuracyPro

/// Round 172 tg-style envelope 자기상관 rate 추정기 회귀 가드.
/// 48kHz 합성 envelope(beat 마다 가우시안 펄스)에서 진값 rate 를 정밀 복원하는지 검증.
final class TgRateEstimatorTests: XCTestCase {

    /// beat 간격마다 가우시안 펄스를 둔 48kHz envelope (tic=toc 대칭).
    private func envelope(bph: Int, duration: Double, sr: Double = 48_000, noise: Float = 0) -> [Float] {
        let n = Int(duration * sr)
        var env = [Float](repeating: 0, count: n)
        let beat = 3600.0 / Double(bph) * sr        // samples per beat
        let width = 50.0                             // 펄스 stddev (~1ms)
        var t = 0.0
        while t < Double(n) {
            let center = Int(t)
            let lo = max(0, center - 220), hi = min(n - 1, center + 220)
            if lo < hi {
                for i in lo...hi {
                    let d = Double(i) - t
                    env[i] += Float(exp(-d * d / (2 * width * width)))
                }
            }
            t += beat
        }
        if noise > 0 {
            var rng = SystemRandomNumberGenerator()
            for i in 0..<n { env[i] += Float.random(in: -noise...noise, using: &rng) }
        }
        return env
    }

    func test_onRate_isNearZero() {
        let r = TgRateEstimator.estimate(envelope: envelope(bph: 28_800, duration: 24), sampleRate: 48_000, nominalBph: 28_800)
        let res = try? XCTUnwrap(r)
        print("🟦 tg on-rate: rate=\(res?.rate ?? .nan) sigma=\(res?.sigma ?? .nan) K=\(res?.cyclesUsed ?? 0)")
        XCTAssertEqual(res?.rate ?? .nan, 0, accuracy: 3)
    }

    func test_fast_recoversPositive() {
        let r = TgRateEstimator.estimate(envelope: envelope(bph: 28_814, duration: 24), sampleRate: 48_000, nominalBph: 28_800)
        let res = try? XCTUnwrap(r)
        print("🟦 tg fast: rate=\(res?.rate ?? .nan) (진값 +42) sigma=\(res?.sigma ?? .nan)")
        XCTAssertEqual(res?.rate ?? .nan, 42, accuracy: 8)
    }

    func test_slow_recoversNegative() {
        let r = TgRateEstimator.estimate(envelope: envelope(bph: 28_786, duration: 24), sampleRate: 48_000, nominalBph: 28_800)
        let res = try? XCTUnwrap(r)
        print("🟦 tg slow: rate=\(res?.rate ?? .nan) (진값 -42) sigma=\(res?.sigma ?? .nan)")
        XCTAssertEqual(res?.rate ?? .nan, -42, accuracy: 8)
    }

    func test_cleanSignal_lowSigma() {
        let r = TgRateEstimator.estimate(envelope: envelope(bph: 28_800, duration: 24), sampleRate: 48_000, nominalBph: 28_800)
        XCTAssertLessThan(r?.sigma ?? .infinity, 8, "깨끗한 신호는 cycle 간 일관 → sigma 작아야")
    }

    func test_withNoise_stillRecovers() {
        // 노이즈를 섞어도 자기상관(전 구간 평균)이라 진값 근처 복원.
        let r = TgRateEstimator.estimate(envelope: envelope(bph: 28_786, duration: 24, noise: 0.3), sampleRate: 48_000, nominalBph: 28_800)
        let res = try? XCTUnwrap(r)
        print("🟦 tg slow+noise: rate=\(res?.rate ?? .nan) (진값 -42)")
        XCTAssertEqual(res?.rate ?? .nan, -42, accuracy: 12)
    }
}
