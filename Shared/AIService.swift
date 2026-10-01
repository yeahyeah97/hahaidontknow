import Foundation
import Security

enum AIAction {
    case fix
    case rewrite
    case translate
    case tone

    var instruction: String {
        switch self {
        case .fix:
            return "Correct spelling, grammar, punctuation, and obvious typing mistakes. Preserve the original meaning, language, slang, and tone. Return only the corrected text."
        case .rewrite:
            return "Rewrite the text so it is clearer and more natural while preserving its meaning and language. Return only the rewritten text."
        case .translate:
            return "Translate Italian to English or English to Italian, automatically detecting the source language. Return only the translation."
        case .tone:
            return "Rewrite the text in a polished, friendly, natural tone while preserving its meaning and language. Return only the rewritten text."
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let keychainService = "com.milazy.keyboard.ai"
    private let keychainAccount = "openai-api-key"

    private init() {}

    var hasAPIKey: Bool {
        apiKey != nil
    }

    func saveAPIKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func clearAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func transform(_ text: String, action: AIAction) async -> String? {
        guard let key = apiKey else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-5.6-luna",
            "instructions": action.instruction,
            "input": text,
            "max_output_tokens": 500
        ]

        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = encoded

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let direct = json["output_text"] as? String, !direct.isEmpty {
                return direct.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let output = json["output"] as? [[String: Any]] {
                for item in output {
                    guard let content = item["content"] as? [[String: Any]] else { continue }
                    for part in content {
                        if let text = part["text"] as? String, !text.isEmpty {
                            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}
