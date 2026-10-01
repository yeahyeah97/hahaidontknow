import Foundation

final class LocalLanguageModel {
    static let shared = LocalLanguageModel()

    private let defaults = UserDefaults.standard
    private let wordKey = "milazy.learned.wordFrequency.v1"
    private let bigramKey = "milazy.learned.bigramFrequency.v1"

    private var words: [String: Int]
    private var bigrams: [String: Int]

    private init() {
        words = defaults.dictionary(forKey: wordKey) as? [String: Int] ?? [:]
        bigrams = defaults.dictionary(forKey: bigramKey) as? [String: Int] ?? [:]
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func learn(word: String, previous: String?) {
        let current = normalized(word)
        guard current.count >= 2, current.rangeOfCharacter(from: .letters) != nil else { return }

        words[current, default: 0] = min(words[current, default: 0] + 1, 50_000)

        if let previous {
            let prev = normalized(previous)
            if !prev.isEmpty {
                let key = prev + "\u{1F}" + current
                bigrams[key, default: 0] = min(bigrams[key, default: 0] + 1, 50_000)
            }
        }

        trimIfNeeded()
        defaults.set(words, forKey: wordKey)
        defaults.set(bigrams, forKey: bigramKey)
    }

    func completions(prefix: String, previous: String?, limit: Int = 8) -> [String] {
        let p = normalized(prefix)
        guard !p.isEmpty else { return nextWords(after: previous, limit: limit) }

        var scored: [(String, Int)] = []
        for (word, count) in words where word.hasPrefix(p) && word != p {
            var score = count * 10
            if let previous {
                let key = normalized(previous) + "\u{1F}" + word
                score += bigrams[key, default: 0] * 40
            }
            scored.append((word, score))
        }
        return scored
            .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    func nextWords(after previous: String?, limit: Int = 8) -> [String] {
        guard let previous else { return [] }
        let prefix = normalized(previous) + "\u{1F}"
        var scored: [(String, Int)] = []
        for (key, count) in bigrams where key.hasPrefix(prefix) {
            let word = String(key.dropFirst(prefix.count))
            let score = count * 40 + words[word, default: 0] * 2
            scored.append((word, score))
        }
        return scored
            .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    func frequency(of word: String) -> Int {
        words[normalized(word), default: 0]
    }

    private func trimIfNeeded() {
        if words.count > 2500 {
            let keep = words.sorted { $0.value > $1.value }.prefix(2000)
            words = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if bigrams.count > 5000 {
            let keep = bigrams.sorted { $0.value > $1.value }.prefix(4000)
            bigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
