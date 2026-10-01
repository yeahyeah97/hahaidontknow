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
            return "Correct spelling, grammar, punctuation, and obvious typing mistakes. Preserve the original meaning, language, slang, abbreviations, and tone. Return only the corrected text, with no explanation."
        case .rewrite:
            return "Rewrite the text so it sounds clearer and more natural while preserving the original meaning and language. Return only the rewritten text, with no explanation."
        case .translate:
            return "Detect whether the text is Italian or English. Translate Italian to English or English to Italian. Preserve names, slang, emojis, and punctuation. Return only the translation."
        case .tone:
            return "Rewrite the text in a polished, friendly, natural tone while preserving its original meaning and language. Return only the rewritten text."
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"
    )!

    private let keychainService = "com.milazy.keyboard.gemini"
    private let keychainAccount = "gemini-api-key"

    private init() {}

    var hasAPIKey: Bool {
        apiKey != nil
    }

    func saveAPIKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return false
        }

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
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": action.instruction]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 512
            ]
        ]

        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = encoded

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]] else {
                return nil
            }

            for candidate in candidates {
                guard let content = candidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    continue
                }

                for part in parts {
                    if let value = part["text"] as? String, !value.isEmpty {
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            return nil
        } catch {
            return nil
        }
    }
}
