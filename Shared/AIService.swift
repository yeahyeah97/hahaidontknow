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
            Reconstruct the intended meaning first, then rewrite the message naturally.

            The input may be fragmented, telegraphic, grammatically non-standard, missing articles/prepositions/verbs, or written in a compressed order where the logical links are only implied. Do NOT correct it word-by-word.

            Work internally in this order:
            1. Identify the concrete topic, people, objects, places, numbers, and actions mentioned.
            2. Infer the practical intent: what is the person asking, explaining, requesting, confirming, or trying to do?
            3. Reconstruct any implicit question/action chain. For example:
               location -> which object -> which visual reference -> open/close? -> how do I use it?
            4. Restore only strongly implied missing verbs, articles, prepositions, pronouns, and connectors.
            5. Reorder the message into natural spoken/written language.
            6. Keep ambiguity when the source is genuinely ambiguous instead of inventing facts.

            Important behavior:
            - Preserve the same language as the input unless the user explicitly asks to translate.
            - Preserve names, usernames, places, numbers, technical terms, slang, emojis, emphasis, and emotional tone.
            - Preserve the person's actual intent, not merely the literal word order.
            - Prefer simple, direct language when the source itself is simple.
            - If several fragments are actually separate implicit questions, write them as separate natural questions.
            - Do not add facts, motives, people, dates, locations, or technical details that are not supported.
            - Do not assume identity, disability, background, or intent beyond what the words/context support.
            - If one fragment is unclear, choose the least-assumptive plausible reading and keep that uncertainty visible.
            - Output ONLY the reconstructed message. No explanation, no analysis, no quotation marks.

            Examples:

            Input:
            "Spiegare ssd come fare mettere dentro pc Lui 4 anni ssd 2TB montare dentro fatto mai"

            Output:
            "Spiegagli come montare l’SSD nel PC: ha un SSD da 2 TB da 4 anni e non l’ha mai montato."

            Input:
            "Sì non ho molta capacità leggere da dove inizio solo tipo Valleggia vicino Quiliano serve metti tipo colore arancione armadio porta e dentro chiusa ok come si usa cellulare non me ne intendo molto"

            Output:
            "Sì, faccio fatica a leggere e non so bene da dove iniziare. Mi basta una spiegazione semplice: dove si trova esattamente a Valleggia, vicino a Quiliano? Quale armadio devo cercare, quello con la porta arancione? E quella porta va aperta o deve restare chiusa? Spiegami anche come si usa con il cellulare, perché non me ne intendo molto."

            Input:
            "domani mamma ospedale io accompagnare poi lavoro tardi"

            Output:
            "Domani accompagno mia mamma in ospedale, poi andrò al lavoro più tardi."

            Input:
            "quale armadio porta arancione dentro chiusa"

            Output:
            "Quale armadio sarebbe? Quello con la porta arancione? E quella porta deve essere aperta o chiusa?"
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
