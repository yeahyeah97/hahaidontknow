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
            - Preserve ALL semantic relationships from the map: who does/thinks/wants/asks what, toward whom/what, under what condition, at what time, and with what intended result.
            - Actor/target/reference relationships are more important than grammatical smoothness.
            - Preserve modality and event status exactly: fact vs wish vs fear vs possibility vs question vs command vs plan.
            - Preserve negation, conditions, causes, comparisons, and contrasts.
            - If the map contains multiple separate intentions or clauses, keep them separate rather than merging them into one smooth but wrong sentence.
            - Turn implied questions into explicit natural questions when the map supports them.
            - If confidence is low for one relation, prefer a conservative wording that does not commit to an unsupported interpretation.
            - Turn object-description fragments into identification questions when appropriate: e.g. "armadio porta arancione" may mean "Quale armadio? Quello con la porta arancione?"
            - Turn state/action fragments into the likely practical question when strongly supported: e.g. "porta chiusa" in an instructional context may mean "deve restare chiusa o va aperta?"
            - Resolve approximate object descriptions from context when safe. Example: "armadio arancione porte pacchi" can naturally become "il locker/armadietto arancione con gli sportelli dove ci sono i pacchi" if the package context is explicit.
            - Keep separate intents separate instead of forcing everything into one long sentence.
            - Prefer simple conversational language over formal language.
            - Do not invent missing facts just to make the sentence smooth.
            - If the semantic map marks something uncertain, phrase that part conservatively.
            - Never mention the semantic map.
            - Output ONLY the reconstructed message, with no explanation and no quotation marks.

            Example:
            ORIGINAL: "Sicuramente Gian se spero sei forte spero zyki ha sconfitta va beneee"
            INTENDED: "Sicuramente, Gian, spero che tu sia forte. E spero che Ziky perda... va beneee."
            Important: this is two separate hopes. Do not rewrite it as "Ziky ha subito una sconfitta", because that changes a desired outcome into a past fact.

            Example:
            ORIGINAL: "Marco no venire io andare se piove forse casa"
            INTENDED: "Marco non viene. Io vado, ma se piove forse resto a casa."
            Important: preserve the negation and the condition; do not turn all fragments into facts.

            Example:
            ORIGINAL: "mamma telefono lei detto dopo lavoro chiamare"
            INTENDED: "Mamma ha detto che mi chiamerà dopo il lavoro."
            Important: resolve who said what and who will perform the later action before rewriting.
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
        SPEAKER_GOAL: the overall communicative goal: ask, explain, request, confirm, wish, warn, complain, compare, instruct, etc.
        ENTITIES_AND_REFERENCES: every person, place, object, pronoun, nickname, number, color, and technical term; resolve which mentions likely refer to the same thing.
        SEMANTIC_ROLES: for each clause/fragment identify agent, target, object, recipient, location, time, cause, condition, and result when present.
        RELATION_GRAPH: connect fragments that belong together even when grammar/connectors are missing.
        MODALITY_SCOPE: who/what words such as hope, want, need, can, must, maybe, probably, fear, think, know, ask, say, and their equivalents apply to.
        DESIRED_OR_FEARED_OUTCOME: what result is wanted, hoped for, avoided, feared, expected, or rejected, and for which person/entity.
        EVENT_STATUS: for every important event, classify it as past fact, present fact, future plan, hypothetical, possibility, wish, fear, command, question, or unknown.
        POLARITY: preserve positive/negative orientation and who benefits/loses; never flip "I hope X loses" into "X lost" or "I don't want Y" into "I want Y".
        IMPLICIT_QUESTIONS: questions that are intended even if question words/punctuation are missing.
        OMITTED_LINKS: likely missing verbs, subjects, articles, prepositions, conjunctions, or comparison links that are strongly implied.
        ACTION_OR_STATE: actions, choices, states, or instructions implied by fragments such as open/closed, inside/outside, this/that, where/which/how.
        UNCERTAINTY: fragments or relationships that cannot be resolved safely.
        CONFIDENCE: mark low-confidence interpretations so the final pass stays conservative.

        Important:
        - Treat short noun clusters as possible compressed questions, not merely broken grammar.
        - Apply semantic-role and scope reasoning to EVERY message, not only messages containing hope/desire words.
        - For every clause-like fragment ask: WHO is doing/thinking/wanting WHAT, TO/ABOUT WHOM or WHAT, WHEN, WHERE, WHY, and with what result?
        - Never assume adjacent words belong to the same event merely because they are next to each other; first test whether they form separate clauses, questions, wishes, or actions.
        - When a modal/mental verb appears (hope, want, fear, think, know, ask, say, need, can, must, etc.), explicitly determine its scope and target before rewriting.
        - Distinguish event tense/status from desired outcome. A noun or adjective can describe a fact, goal, fear, or hypothetical depending on surrounding scope markers.
        - Preserve causal and conditional logic. Do not turn "if X then Y" into two independent facts, or "because X" into an unrelated statement.
        - Preserve negation exactly. A missing or misplaced "non/no" can completely reverse meaning, so infer it conservatively and never remove it without strong support.
        - Resolve pronouns and approximate labels from context, but keep uncertainty if multiple referents are plausible.
        - Use proximity and practical context to resolve references: an adjective/color after an object may identify which object; a state word may ask what to do with that object.
        - Treat everyday object labels as possibly approximate. For example, "armadio" together with "pacchi", "sportelli/porte", a color, and opening/closing may refer to a parcel locker rather than a literal wardrobe. Only make that inference when the surrounding words support it.
        - Reconstruct the smallest plausible chain of meaning.
        - Do not invent facts, identities, motives, locations, or actions unsupported by the text.
        - Do not assume anything about the writer's disability, education, or background.
        - Keep uncertainty explicit instead of guessing confidently.
        - Be concise. This semantic map is for a second model pass, not for the user.
        """
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
