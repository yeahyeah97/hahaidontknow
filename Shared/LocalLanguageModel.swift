import Foundation

// Access is serialized by PredictionEngine's worker. Immutable snapshots are
// published to the UI; the input path never reads or writes UserDefaults.
final class LocalLanguageModel {
    struct Snapshot {
        var words: [String: Int]
        var bigrams: [String: Int]
        var corrections: [String: Int]

        func frequency(of word: String) -> Int { words[word.lowercased(), default: 0] }
        func corrections(for source: String) -> [(String, Int)] {
            let prefix = source.lowercased() + "\u{1F}"
            return corrections.compactMap { key, count in
                key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), count) : nil
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        }
        func contextFrequency(_ word: String, previous: String?) -> Int {
            guard let previous else { return 0 }
            return bigrams[previous.lowercased() + "\u{1F}" + word.lowercased(), default: 0]
        }
        func completions(prefix: String, previous: String?, limit: Int = 8) -> [String] {
            let lower = prefix.lowercased()
            let values = words.keys.filter { $0.hasPrefix(lower) && $0 != lower }
            return Array(values.sorted {
                let l = frequency(of: $0) + contextFrequency($0, previous: previous) * 4
                let r = frequency(of: $1) + contextFrequency($1, previous: previous) * 4
                return l == r ? $0 < $1 : l > r
            }.prefix(limit))
        }
        func nextWords(after previous: String?, limit: Int = 8) -> [String] {
            guard let previous else { return [] }
            let prefix = previous.lowercased() + "\u{1F}"
            let values = bigrams.keys.filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
            return Array(values.sorted {
                let l = contextFrequency($0, previous: previous)
                let r = contextFrequency($1, previous: previous)
                return l == r ? $0 < $1 : l > r
            }.prefix(limit))
        }
    }

    private let defaults: UserDefaults
    private let wordKey = "milazy.learned.wordFrequency.v1"
    private let bigramKey = "milazy.learned.bigramFrequency.v1"
    private let correctionKey = "milazy.learned.correctionFrequency.v1"
    private var state: Snapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Snapshot(
            words: defaults.dictionary(forKey: wordKey) as? [String: Int] ?? [:],
            bigrams: defaults.dictionary(forKey: bigramKey) as? [String: Int] ?? [:],
            corrections: defaults.dictionary(forKey: correctionKey) as? [String: Int] ?? [:]
        )
        trim()
    }

    func snapshot() -> Snapshot { state }

    func learn(word: String, previous: String?) {
        let word = word.lowercased()
        guard (2...40).contains(word.count), word.contains(where: { $0.isLetter }) else { return }
        state.words[word, default: 0] = min(state.words[word, default: 0] + 1, 50_000)
        if let previous, !previous.isEmpty {
            let key = previous.lowercased() + "\u{1F}" + word
            state.bigrams[key, default: 0] = min(state.bigrams[key, default: 0] + 1, 50_000)
        }
        trim()
    }

    func learnCorrection(from source: String, to replacement: String) {
        let source = source.lowercased(), replacement = replacement.lowercased()
        guard source != replacement, !source.isEmpty, !replacement.isEmpty,
              source.count <= 40, replacement.count <= 80 else { return }
        let key = source + "\u{1F}" + replacement
        state.corrections[key, default: 0] = min(state.corrections[key, default: 0] + 1, 50_000)
        trim()
    }

    func rejectCorrection(for source: String) {
        let prefix = source.lowercased() + "\u{1F}"
        state.corrections = state.corrections.filter { !$0.key.hasPrefix(prefix) }
        learn(word: source, previous: nil)
        learn(word: source, previous: nil)
    }

    func persist() {
        defaults.set(state.words, forKey: wordKey)
        defaults.set(state.bigrams, forKey: bigramKey)
        defaults.set(state.corrections, forKey: correctionKey)
    }

    func resetLearning() {
        state = Snapshot(words: [:], bigrams: [:], corrections: [:])
        persist()
    }

    private func trim() {
        func bounded(_ values: [String: Int], maximum: Int, keep: Int) -> [String: Int] {
            guard values.count > maximum else { return values }
            let ranked = values.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            return Dictionary(uniqueKeysWithValues: ranked.prefix(keep).map { ($0.key, $0.value) })
        }
        state.words = bounded(state.words, maximum: 12000, keep: 10000)
        state.bigrams = bounded(state.bigrams, maximum: 24000, keep: 20000)
        state.corrections = bounded(state.corrections, maximum: 8000, keep: 6000)
    }
}


