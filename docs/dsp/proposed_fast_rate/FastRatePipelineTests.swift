import XCTest
@testable import WatchAccuracyPro

// 제안 알고리즘 테스트(작성자 제공). ⚠️ 합성 신호가 onset 시각을 직접 생성하므로
// 실제 오디오→envelope→50ms 청크 onset 경로의 시각 양자화·위상편향은 검증하지 않음.

// MARK: - KalmanRateFilterTests

final class KalmanRateFilterTests: XCTestCase {

    func test_singleUpdate_bootstrapsEstimate() {
        var filter = KalmanRateFilter()
        filter.update(measurement: 5.0)
        XCTAssertEqual(filter.estimate, 5.0)
        XCTAssertEqual(filter.updateCount, 1)
        XCTAssertTrue(filter.isInitialised)
    }

    func test_multipleUpdates_convergesOnTrueRate() {
        var filter = KalmanRateFilter()
        let trueRate = 3.0
        for _ in 0..<20 {
            filter.update(measurement: trueRate + Double.random(in: -4...4))
        }
        XCTAssertEqual(filter.estimate, trueRate, accuracy: 1.5)
        XCTAssertTrue(filter.isConverged)
    }

    func test_convergence_varianceDropsBelowThreshold() {
        var filter = KalmanRateFilter()
        for _ in 0..<15 { filter.update(measurement: 2.0) }
        XCTAssertLessThan(filter.variance, filter.convergenceVariance)
        XCTAssertLessThan(filter.standardDeviation, 0.5)
    }

    func test_reset_clearsAllState() {
        var filter = KalmanRateFilter()
        filter.update(measurement: 5.0)
        filter.reset()
        XCTAssertFalse(filter.isInitialised)
        XCTAssertEqual(filter.updateCount, 0)
        XCTAssertFalse(filter.isConverged)
    }

    func test_initiallyNotConverged() {
        let filter = KalmanRateFilter()
        XCTAssertFalse(filter.isInitialised)
        XCTAssertFalse(filter.isConverged)
    }
}

// MARK: - IOIRateEstimatorTests

final class IOIRateEstimatorTests: XCTestCase {

    func test_28800bph_syntheticSignal_convergesUnder8Seconds() {
        var est = IOIRateEstimator()
        est.nominalBPH = 28800
        let trueRate = 3.0
        let nomHP = 3600.0 / 28800.0
        let adjHP = nomHP * (1.0 - trueRate / 86400.0)
        var t = 0.0, parity = 0
        while !est.isConverged && t < 15.0 {
            t += adjHP + Double.random(in: -0.0005...0.0005)
            est.addOnset(time: t, parity: parity)
            parity += 1
        }
        XCTAssertTrue(est.isConverged)
        XCTAssertLessThan(t, 8.0)
        XCTAssertEqual(est.rateSecPerDay, trueRate, accuracy: 1.5)
    }

    func test_18000bph_syntheticSignal_convergesUnder12Seconds() {
        var est = IOIRateEstimator()
        est.nominalBPH = 18000
        let trueRate = -5.0
        let nomHP = 3600.0 / 18000.0
        let adjHP = nomHP * (1.0 + 5.0 / 86400.0)
        var t = 0.0, parity = 0
        while !est.isConverged && t < 20.0 {
            t += adjHP + Double.random(in: -0.001...0.001)
            est.addOnset(time: t, parity: parity)
            parity += 1
        }
        XCTAssertTrue(est.isConverged)
        XCTAssertLessThan(t, 12.0)
        XCTAssertEqual(est.rateSecPerDay, trueRate, accuracy: 2.0)
    }

    func test_madFilter_outlierOnset_doesNotBreakEstimate() {
        var est = IOIRateEstimator()
        est.nominalBPH = 28800
        let hp = 0.125
        var t = 0.0
        for i in 0..<12 { t += hp; est.addOnset(time: t, parity: i) }
        let rateBeforeOutlier = est.rateSecPerDay
        est.addOnset(time: t + 0.010, parity: 12)
        XCTAssertEqual(est.rateSecPerDay, rateBeforeOutlier, accuracy: 2.0)
    }

    func test_beatError_symmetricSignal_nearZero() {
        var est = IOIRateEstimator()
        est.nominalBPH = 28800
        var t = 0.0
        for i in 0..<20 { t += 0.125; est.addOnset(time: t, parity: i) }
        if let be = est.beatErrorMs {
            XCTAssertLessThan(be, 1.0)
        }
    }

    func test_reset_clearsAllTimestamps() {
        var est = IOIRateEstimator()
        est.nominalBPH = 28800
        for i in 0..<10 { est.addOnset(time: Double(i) * 0.125, parity: i) }
        est.reset()
        XCTAssertFalse(est.isConverged)
        XCTAssertEqual(est.confidenceScore, 0)
    }
}

// MARK: - AdaptiveOnsetDetectorTests

final class AdaptiveOnsetDetectorTests: XCTestCase {

    func test_detectsOnset_clearPeakAboveBackground() {
        let det = AdaptiveOnsetDetector(bph: 28800, chunkDuration: 0.05)
        for _ in 0..<30 { let _ = det.process(envelopePeak: 0.01) }
        let result = det.process(envelopePeak: 0.5)
        XCTAssertNotNil(result)
    }

    func test_refractoryPeriod_blocksRapidRetrigger() {
        let det = AdaptiveOnsetDetector(bph: 28800, chunkDuration: 0.05)
        for _ in 0..<30 { let _ = det.process(envelopePeak: 0.01) }
        let first = det.process(envelopePeak: 1.0)
        let second = det.process(envelopePeak: 1.0)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
    }

    func test_refractoryPeriod_28800bph_is106ms() {
        let det = AdaptiveOnsetDetector(bph: 28800)
        let expected = (3600.0 / 28800.0) * 0.85
        XCTAssertEqual(det.refractoryPeriod, expected, accuracy: 0.001)
    }

    func test_refractoryPeriod_18000bph_is170ms() {
        let det = AdaptiveOnsetDetector(bph: 18000)
        let expected = (3600.0 / 18000.0) * 0.85
        XCTAssertEqual(det.refractoryPeriod, expected, accuracy: 0.001)
    }
}

// MARK: - GoertzelTests

final class GoertzelBPHEstimatorTests: XCTestCase {

    func test_28800bph_syntheticImpulse_identified() {
        let sampleRate = 48_000.0
        let duration = 1.5
        let halfBeatHz = 28800.0 / 7200.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * duration))
        let period = Int(sampleRate / halfBeatHz)
        for i in stride(from: 0, to: samples.count, by: period) { samples[i] = 1.0 }
        let result = BPHEstimator.goertzelEstimate(envelopeSamples: samples, sampleRate: sampleRate)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.bph, 28800)
        XCTAssertGreaterThan(result!.confidence, 0.5)
    }

    func test_insufficientBuffer_returnsNil() {
        let samples = [Float](repeating: 0.1, count: 100)
        let result = BPHEstimator.goertzelEstimate(envelopeSamples: samples, sampleRate: 48_000)
        XCTAssertNil(result)
    }

    func test_knownBPH_fullConfidence() {
        let est = BPHEstimator.knownBPHEstimate(28800)
        XCTAssertEqual(est.bph, 28800)
        XCTAssertEqual(est.confidence, 1.0)
        XCTAssertEqual(est.source, .movementDB)
    }
}
