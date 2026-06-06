import AudioToolbox

/// 측정 사운드 중앙화 — 기계식 'tick' 느낌의 짧은 시스템 사운드. 기본 OFF(소리는 방해될 수 있어 옵트인).
/// `UserPreferences.measurementSoundEnabled`(UserDefaults)를 매 호출 시 참조 → 토글 즉시 반영.
/// HapticManager 와 동일 패턴. 햅틱과 독립(둘 다/하나만/끔 가능).
enum SoundManager {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "ticklab.measurementSound") as? Bool ?? false
    }

    /// BPH 락 등 '딱' 걸리는 순간 — 약간 높은 틱.
    static func playLock() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1103)   // Tink
    }

    /// 측정 완료 — 깔끔한 톡.
    static func playComplete() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1104)   // Tock
    }
}
