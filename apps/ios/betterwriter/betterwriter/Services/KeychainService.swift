import Foundation
import Security

/// Manages the persistent device UUID and auth token stored in Keychain.
/// The device ID survives app reinstalls and is used to identify the user on the server.
/// The auth token is a server-signed JWT exchanged for the device ID.
enum KeychainService {
  private static let service = "com.betterwriter.device-id"
  private static let accountDeviceId = "device-uuid"
  private static let accountAuthToken = "auth-token"

  // MARK: - Device ID

  /// Get existing device ID or create a new one.
  /// In DEBUG builds, set the `DEBUG_DEVICE_ID` environment variable in the
  /// Xcode scheme to force a specific UUID (useful for testing against
  /// an existing server account).
  nonisolated static func getOrCreateDeviceId() -> UUID {
    #if DEBUG
      if let override = ProcessInfo.processInfo
        .environment["DEBUG_DEVICE_ID"],
        let uuid = UUID(uuidString: override)
      {
        // Persist so the rest of the app (and re-launches) stay consistent.
        saveDeviceId(uuid)
        deleteAuthToken()  // force re-auth with the new identity
        return uuid
      }
    #endif
    if let existing = getDeviceId() {
      return existing
    }
    let newId = UUID()
    saveDeviceId(newId)
    return newId
  }

  /// Read device ID from Keychain.
  nonisolated static func getDeviceId() -> UUID? {
    guard let data = readItem(account: accountDeviceId),
      let uuidString = String(data: data, encoding: .utf8),
      let uuid = UUID(uuidString: uuidString)
    else {
      return nil
    }
    return uuid
  }

  /// Save device ID to Keychain.
  nonisolated private static func saveDeviceId(_ uuid: UUID) {
    let data = uuid.uuidString.data(using: .utf8)!
    saveItem(account: accountDeviceId, data: data)
  }

  // MARK: - Auth Token (JWT)

  /// Read the stored auth token.
  nonisolated static func getAuthToken() -> String? {
    guard let data = readItem(account: accountAuthToken),
      let token = String(data: data, encoding: .utf8),
      !token.isEmpty
    else {
      return nil
    }
    return token
  }

  /// Save the auth token to Keychain.
  nonisolated static func saveAuthToken(_ token: String) {
    let data = token.data(using: .utf8)!
    saveItem(account: accountAuthToken, data: data)
  }

  /// Delete the stored auth token (e.g. on logout or forced re-auth).
  nonisolated static func deleteAuthToken() {
    deleteItem(account: accountAuthToken)
  }

  // MARK: - Generic Keychain Helpers

  nonisolated private static func readItem(account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return data
  }

  nonisolated private static func saveItem(account: String, data: Data) {
    // Build a delete query (without kSecValueData)
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    if status != errSecSuccess {
      print("KeychainService: Failed to save item (\(account)), status: \(status)")
    }
  }

  nonisolated private static func deleteItem(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
