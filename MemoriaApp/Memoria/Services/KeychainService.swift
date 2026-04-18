// KeychainService.swift
// Memoria for iPhone - Secure API Key Storage
// Phase 6: クラウドAI APIキーをiOS Keychainに安全保管

import Foundation
import Security

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case gemini = "com.memoria.api.gemini"
    case claude = "com.memoria.api.claude"
    case openai = "com.memoria.api.openai"

    /// Identifiable: rawValue をIDとして使用（.sheet(item:) 対応）
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        }
    }

    var displayIcon: String {
        switch self {
        case .gemini: return "sparkles"
        case .claude: return "wand.and.stars"
        case .openai: return "brain.head.profile"
        }
    }

    var keyObtainURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .claude: return "https://console.anthropic.com/settings/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        }
    }

    var keyPrefix: String {
        switch self {
        case .gemini: return "AIza"
        case .claude: return "sk-ant-"
        case .openai: return "sk-"
        }
    }

    /// APIキーの形式が正しいか簡易チェック
    func isValidKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        return trimmed.hasPrefix(keyPrefix)
    }
}

// MARK: - KeychainService

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    // MARK: - Set

    @discardableResult
    func setAPIKey(_ key: String, for provider: APIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        // 既存エントリを削除（更新のため）
        deleteAPIKey(for: provider)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "Memoria",
            kSecAttrAccount as String:      provider.rawValue,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Get

    func getAPIKey(for provider: APIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "Memoria",
            kSecAttrAccount as String:      provider.rawValue,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    // MARK: - Delete

    func deleteAPIKey(for provider: APIProvider) {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  "Memoria",
            kSecAttrAccount as String:  provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Check

    func hasAPIKey(for provider: APIProvider) -> Bool {
        getAPIKey(for: provider) != nil
    }

    /// マスク表示用（最初4文字 + ****）
    func maskedKey(for provider: APIProvider) -> String? {
        guard let key = getAPIKey(for: provider), key.count >= 8 else { return nil }
        let prefix = String(key.prefix(8))
        return "\(prefix)••••••••••••"
    }
}
