import Foundation

/// Beat 검출 알고리즘의 추상화.
/// Phase 1 의 Onset-based 검출(`OnsetBeatDetector`) 와 Phase 2 의 CoreML 검출(`CoreMLBeatDetector`) 가 같은 인터페이스를 만족.
protocol BeatDetecting {
    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent]
}

/// 기존 `BeatDetector` 정적 메서드를 protocol 인스턴스로 감싸 사용.
struct OnsetBeatDetector: BeatDetecting {
    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent] {
        BeatDetector.detectOnsets(envelope: envelope, sampleRate: sampleRate)
    }
}
