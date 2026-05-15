import Foundation
import CryptoKit
import Security

/// 커스텀 6자리 PIN 인증 (디바이스 Face ID 와 별개).
/// - PIN 자체는 저장하지 않음. SHA256 해시만 Keychain (WhenUnlockedThisDeviceOnly) 저장.
/// - 5회 연속 실패 시 PIN 비활성 → Face ID 만으로 잠금 해제 가능 (Face ID 성공 시 카운터 리셋).
/// - Hard Rule 8: 외부 전송 없음, 전부 on-device.
@MainActor
final class PINService: ObservableObject {
    static let shared = PINService()

    // MARK: - Keychain / UserDefaults keys

    private enum K {
        static let pinHashAccount = "com.ticklab.pin.hash"
        static let failureCount   = "com.ticklab.pin.failureCount"
    }

    static let maxFailureAttempts: Int = 5
    static let pinLength: Int = 6

    // MARK: - Public reactive state (View 갱신용)

    /// 현재 실패 카운터. UI 의 잔여 시도 횟수 표기에 사용.
    @Published private(set) var failureCount: Int

    /// 설정 여부. View 가 토글/상태 표시에 사용.
    @Published private(set) var hasPIN: Bool

    private init() {
        self.failureCount = UserDefaults.standard.integer(forKey: K.failureCount)
        self.hasPIN = Self.loadHash() != nil
    }

    // MARK: - Locked-out 상태

    /// 5회 연속 실패 도달 — PIN 화면 비활성, Face ID 강제.
    var isPINLockedOut: Bool {
        failureCount >= Self.maxFailureAttempts
    }

    // MARK: - PIN 설정 / 변경

    /// PIN 설정 또는 변경. 6자리 숫자가 아니면 throw.
    func setPIN(_ pin: String) throws {
        guard Self.isValidPINFormat(pin) else { throw PINError.invalidFormat }
        let hash = Self.hash(pin)
        try Self.saveHash(hash)
        hasPIN = true
        resetFailureCount()
    }

    // MARK: - 검증

    /// PIN 검증. 형식 불일치 → false (카운트 안 함). 일치 → 실패 카운터 리셋.
    func verifyPIN(_ pin: String) -> Bool {
        guard Self.isValidPINFormat(pin) else { return false }
        guard let stored = Self.loadHash() else { return false }
        let candidate = Self.hash(pin)
        // CryptoKit 의 Digest 비교 — constant-time 비교를 위해 byte sequence 비교.
        let match = Self.constantTimeEqual(stored, candidate)
        if match {
            resetFailureCount()
            return true
        } else {
            incrementFailureCount()
            return false
        }
    }

    // MARK: - PIN 제거

    func clearPIN() {
        Self.deleteHash()
        hasPIN = false
        resetFailureCount()
    }

    // MARK: - Failure counter

    /// Face ID 성공 등에서 호출 — 실패 카운터를 초기화.
    func resetFailureCount() {
        failureCount = 0
        UserDefaults.standard.set(0, forKey: K.failureCount)
    }

    private func incrementFailureCount() {
        failureCount = min(failureCount + 1, Self.maxFailureAttempts)
        UserDefaults.standard.set(failureCount, forKey: K.failureCount)
    }

    // MARK: - Helpers (static)

    static func isValidPINFormat(_ pin: String) -> Bool {
        guard pin.count == pinLength else { return false }
        return pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func hash(_ pin: String) -> Data {
        let digest = SHA256.hash(data: Data(pin.utf8))
        return Data(digest)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    // MARK: - Keychain access

    private static func keychainQueryBase() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: K.pinHashAccount,
        ]
    }

    private static func loadHash() -> Data? {
        var query = keychainQueryBase()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func saveHash(_ hash: Data) throws {
        // 기존 항목 제거 후 새로 추가 (변경 시 덮어쓰기).
        let deleteQuery = keychainQueryBase()
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = keychainQueryBase()
        addQuery[kSecValueData as String] = hash
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PINError.keychain(status: status)
        }
    }

    private static func deleteHash() {
        let query = keychainQueryBase()
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum PINError: Error {
    case invalidFormat
    case keychain(status: OSStatus)
}
