import Foundation

// Immutable and shared by the worker/UI snapshots. Personal learning never
// rebuilds these signatures or copies their storage onto the main queue.
final class SpellVocabulary {
    struct Entry {
        let word: String
        var italian: Double = 0
        var english: Double = 0

        func frequency(mode: KeyboardPreferences.LanguageMode) -> Double {
            switch mode {
            case .automatic: return max(italian, english)
            case .italian: return italian
            case .english: return english
            }
        }
    }

    private let entries: [Entry]
    private let lookup: [String: Int]
    private let signatures: [String: [Int]]
    var count: Int { entries.count }

    init(italian: [(String, Double)], english: [(String, Double)]) {
        var values: [String: Entry] = [:]
        for (word, frequency) in italian {
            values[word, default: Entry(word: word)].italian = frequency
        }
        for (word, frequency) in english {
            values[word, default: Entry(word: word)].english = frequency
        }
        entries = values.values.sorted { $0.word < $1.word }
        var lookup: [String: Int] = [:]
        var signatures: [String: [Int]] = [:]
        for (id, entry) in entries.enumerated() {
            lookup[entry.word] = id
            for key in CorrectionIndex.deletions(entry.word) {
                signatures[key, default: []].append(id)
            }
        }
        self.lookup = lookup
        self.signatures = signatures
    }

    func frequency(_ word: String, mode: KeyboardPreferences.LanguageMode) -> Double {
        guard let id = lookup[word.lowercased()] else { return 0 }
        return entries[id].frequency(mode: mode)
    }

    func candidates(for word: String, mode: KeyboardPreferences.LanguageMode) -> [Entry] {
        var ids: Set<Int> = []
        for key in CorrectionIndex.deletions(word) {
            ids.formUnion(signatures[key] ?? [])
        }
        // Ranking is bounded even for noisy short tokens with many neighbors.
        return ids.compactMap { id -> Entry? in
            let entry = entries[id]
            guard entry.frequency(mode: mode) > 0,
                  CorrectionIndex.editDistance(word, entry.word) <= 1 else { return nil }
            return entry
        }.sorted {
            let l = $0.frequency(mode: mode), r = $1.frequency(mode: mode)
            return l == r ? $0.word < $1.word : l > r
        }.prefix(64).map { $0 }
    }

    static func load(directory: URL) -> SpellVocabulary? {
        func read(_ language: String) -> [(String, Double)]? {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(language + ".tsv"),
                                         encoding: .utf8) else { return nil }
            return text.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\t")
                guard fields.count == 2, let value = Double(fields[1]) else { return nil }
                return (String(fields[0]), value)
            }
        }
        guard let italian = read("it"), let english = read("en") else { return nil }
        return SpellVocabulary(italian: italian, english: english)
    }
}
