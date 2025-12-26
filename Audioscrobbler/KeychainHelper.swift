import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private init() {}
    
    private let service = "com.tonioriol.scroblebler"
    private let accessGroup = "com.tonioriol.scroblebler"
    
    // MARK: - Save Password
    
    func savePassword(username: String, password: String) throws {
        // First delete any existing password
        try? deletePassword(username: username)
        
        // Prepare query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: password.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        // Add to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status: status)
        }
    }
    
    // MARK: - Retrieve Password
    
    func getPassword(username: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToRetrieve(status: status)
        }
        
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return password
    }
    
    // MARK: - Delete Password
    
    func deletePassword(username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status: status)
        }
    }
    
    // MARK: - Errors
    
    enum KeychainError: LocalizedError {
        case unableToSave(status: OSStatus)
        case unableToRetrieve(status: OSStatus)
        case unableToDelete(status: OSStatus)
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .unableToSave(let status):
                return "Unable to save to Keychain (status: \(status))"
            case .unableToRetrieve(let status):
                return "Unable to retrieve from Keychain (status: \(status))"
            case .unableToDelete(let status):
                return "Unable to delete from Keychain (status: \(status))"
            case .invalidData:
                return "Invalid data retrieved from Keychain"
            }
        }
    }
}
