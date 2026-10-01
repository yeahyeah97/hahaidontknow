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
            Rewrite the original fragmented message into the most likely natural message, using the supplied semantic map only as an interpretation aid.

            The ORIGINAL TEXT is always the source of truth. The SEMANTIC MAP is a hypothesis about its intent.

            Rules:
            - Preserve the original language.
            - Preserve names, places, numbers, technical terms, slang, emojis, emotional tone, and concrete facts.
            - Recover the intended practical meaning, not the literal word order.
            - Turn implied questions into explicit natural questions.
            - Turn object-description fragments into identification questions when appropriate: e.g. "armadio porta arancione" may mean "Quale armadio? Quello con la porta arancione?"
            - Turn state/action fragments into the likely practical question when strongly supported: e.g. "porta chiusa" in an instructional context may mean "deve restare chiusa o va aperta?"
            - Keep separate intents separate instead of forcing everything into one long sentence.
            - Prefer simple conversational language over formal language.
            - Do not invent missing facts just to make the sentence smooth.
            - If the semantic map marks something uncertain, phrase that part conservatively.
            - Never mention the semantic map.
            - Output ONLY the reconstructed message, with no explanation and no quotation marks.
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

private extension AIAction {
    var semanticAnalysisInstruction: String {
        """
        Analyze the fragmented message before rewriting it. Do NOT produce the final polished sentence.

        Build a compact semantic map with these fields:
        INTENT: what the person is practically trying to ask, explain, confirm, request, or do.
        TOPIC: the central subject.
        ENTITIES: people, places, objects, numbers, colors, technical terms, and other concrete references.
        IMPLICIT_QUESTIONS: questions that are probably intended even if question words or punctuation are missing.
        LINKS: how nearby fragments most likely relate to each other.
        ACTION_OR_STATE: actions, choices, states, or instructions implied by fragments such as open/closed, inside/outside, this/that, where/which/how.
        UNCERTAINTY: fragments that cannot be resolved safely.

        Important:
        - Treat short noun clusters as possible compressed questions, not merely broken grammar.
        - Use proximity and practical context to resolve references: an adjective/color after an object may identify which object; a state word may ask what to do with that object.
        - Reconstruct the smallest plausible chain of meaning.
        - Do not invent facts, identities, motives, locations, or actions unsupported by the text.
        - Do not assume anything about the writer's disability, education, or background.
        - Keep uncertainty explicit instead of guessing confidently.
        - Be concise. This semantic map is for a second model pass, not for the user.
        """
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

        if action == .fix {
            let map = await generate(
                text: text,
                instruction: action.semanticAnalysisInstruction,
                apiKey: key,
                maxOutputTokens: 420
            )

            if let map, !map.isEmpty {
                let combined = """
                ORIGINAL TEXT:
                \(text)

                SEMANTIC MAP:
                \(map)
                """
                if let final = await generate(
                    text: combined,
                    instruction: action.instruction,
                    apiKey: key,
                    maxOutputTokens: 512
                ) {
                    return final
                }
            }
        }

        return await generate(
            text: text,
            instruction: action.instruction,
            apiKey: key,
            maxOutputTokens: 512
        )
    }

    private func generate(
        text: String,
        instruction: String,
        apiKey key: String,
        maxOutputTokens: Int
    ) async -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": instruction]
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
                "maxOutputTokens": maxOutputTokens
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
