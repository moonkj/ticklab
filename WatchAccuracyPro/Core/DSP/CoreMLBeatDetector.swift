import CoreML
import Foundation

/// CoreML 기반 beat 검출기 hook.
///
/// Phase 2 베타: 모델 파일 (`BeatDetector.mlmodel`) 이 번들에 포함된 경우에만 활성화.
/// 모델 출력은 frame 별 beat probability 를 가정하며, 임계치 초과 + refractory 30ms 적용.
/// 모델이 없거나 로드 실패 시 자동으로 OnsetBeatDetector 로 fall-back 한다.
final class CoreMLBeatDetector: BeatDetecting {
    private let model: MLModel?
    private let fallback: BeatDetecting
    private let threshold: Double

    init(modelName: String = "BeatDetector", threshold: Double = 0.5, fallback: BeatDetecting = OnsetBeatDetector()) {
        self.threshold = threshold
        self.fallback = fallback
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            self.model = try? MLModel(contentsOf: url)
        } else {
            self.model = nil
        }
    }

    var isModelAvailable: Bool { model != nil }

    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent] {
        guard let model else {
            return fallback.detect(envelope: envelope, sampleRate: sampleRate)
        }
        // 실제 모델 입출력 shape 은 학습 시 결정됨.
        // 베타에서는 protocol 만 정의하고 fall-back 으로 안전하게 동작.
        // TODO(phase2-coreml): 모델 입출력 spec 확정 후 inference 구현 + 테스트.
        _ = model
        return fallback.detect(envelope: envelope, sampleRate: sampleRate)
    }
}
