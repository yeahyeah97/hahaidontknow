import Foundation

enum SemanticFixRouting {
    // Classification runs only after the user invokes Fix. A fast request still
    // preserves semantics; this heuristic reserves a separate map for fragments.
    static func needsDeepPass(_ text: String, verbCount: Int) -> Bool {
        let words = TextContext.words(in: text).map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        let tokens = Set(words)
        let greetings: Set<String> = ["ciao", "grazie", "buongiorno", "buonasera", "hello", "hi", "thanks", "ok"]
        if words.count <= 2 && !tokens.isDisjoint(with: greetings) { return false }
        let scope: Set<String> = ["spero", "voglio", "vorrei", "penso", "credo", "temo",
                                 "hope", "want", "wish", "think", "fear", "maybe", "forse"]
        let links: Set<String> = ["che", "that", "because", "perché", "quando", "when"]
        let infinitives: Set<String> = ["venire", "andare", "chiamare", "fare", "vedere",
                                       "dire", "aprire", "chiudere", "essere"]
        let auxiliaries: Set<String> = ["ho", "hai", "ha", "hanno", "abbiamo", "avete",
                                       "sono", "sei", "siamo", "siete", "è",
                                       "have", "has", "had", "is", "was", "were"]
        let participles: Set<String> = ["detto", "fatto", "visto", "andato", "chiamato", "sconfitto"]
        if verbCount == 0 { return true }
        if !tokens.isDisjoint(with: participles) && tokens.isDisjoint(with: auxiliaries) { return true }
        if words.filter({ infinitives.contains($0) }).count >= 2 { return true }
        if words.filter({ scope.contains($0) }).count >= 2 && tokens.isDisjoint(with: links) { return true }
        if words.count <= 5 { return false }
        let clausePunctuation = text.contains(where: { ".!?;,".contains($0) })
        let subjects = words.filter { ["io", "tu", "lui", "lei", "noi", "voi", "i", "you", "he", "she", "we", "they"].contains($0) }
        return !clausePunctuation && tokens.isDisjoint(with: links) &&
            subjects.count >= 2 && words.count >= 8
    }
}

