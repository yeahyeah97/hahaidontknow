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
            return """
            Reconstruct the intended meaning first, then rewrite the text naturally.

            The input may be fragmented, telegraphic, grammatically non-standard, or influenced by sign-language word order. Do NOT correct it word-by-word. Infer the logical relationships between the words and clauses, restore omitted articles/prepositions/verbs when strongly implied, and reorder the sentence when needed so the intended meaning becomes clear.

            Rules:
            - Keep the same language as the input unless the user explicitly asks to translate.
            - Preserve names, usernames, numbers, technical terms, slang, emojis, emphasis, and emotional tone.
            - Preserve the person's actual intent; do not make the message more formal unless needed for clarity.
            - Use surrounding words to resolve likely meaning.
            - Do not invent new facts, motives, people, dates, or details.
            - If one fragment is genuinely ambiguous, choose the least-assumptive plausible reading and preserve uncertainty rather than hallucinating.
            - Output ONLY the reconstructed natural sentence/message, with no explanation or quotation marks.

            Examples:
            Input: "Spiegare ssd come fare mettere dentro pc Lui 4 anni ssd 2TB montare dentro fatto mai"
            Output: "Spiegagli come montare l’SSD nel PC: ha un SSD da 2 TB da 4 anni e non l’ha mai montato."

            Input: "io ieri andare palestra lui non venire perché lavoro tanto"
            Output: "Ieri sono andato in palestra, ma lui non è venuto perché aveva molto lavoro."

            Input: "domani mamma ospedale io accompagnare poi lavoro tardi"
            Output: "Domani accompagno mia mamma in ospedale, poi andrò al lavoro più tardi."
            """
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
