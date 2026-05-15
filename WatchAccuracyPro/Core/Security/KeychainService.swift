import Foundation
import Security

/// 시계 시리얼번호 등 민감 정보 Keychain 저장.
/// SwiftData @Model 에는 ID 만, 실제 시리얼은 여기에.
/// Pivot Addendum Security 명세: 시리얼은 plaintext 로 SwiftData 에 두면 안 됨.
enum KeychainService {
    /// Account 형식: "watchSerial.<watch UUID string>"
    static func setSerial(_ serial: String, for watchId: UUID) {
        let account = key(for: watchId)
        let data = Data(serial.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func serial(for watchId: UUID) -> String? {
        let account = key(for: watchId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteSerial(for watchId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(for: watchId),
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func key(for watchId: UUID) -> String {
        "watchSerial.\(watchId.uuidString)"
    }
}
