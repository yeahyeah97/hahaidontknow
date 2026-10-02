import Foundation

// Shared frequency data supplements UITextChecker and supplies immediate local
// decisions when the last asynchronous spellcheck has not finished.
struct CorrectionIndex {
    private static let italian = """
    a ad al alla allo alle ai agli anche ancora andare anno anni amico amica amici
    amore arrivare aspetta aspettare abbiamo bene boh buongiorno buonasera casa ciao che
    chi chiamare chiamato chiamo ci città come comprare con cosa cose così da dai dal
    dalla delle devo devi deve devono dire di dopo dove e è essere era ero ero eri
    erano fa fai fare fatto farò figlio figlia fine forse grazie già giorno giorni
    gli hai ha hanno ho il io la le lo loro lui lei lavoro lavorare ma mangiare
    mamma me meglio mi mia mie mio miei molto mondo ne nel nella niente no non noi
    oggi ok ora papà per perché però piacere piace più poi posso puoi può possiamo
    potrei prima problema qua qui quando quanto questo questa questi quello quella
    quindi ragazzo ragazza ragazzi ragazze resto sapere sei siamo siete sì si sono
    spero speriamo sta stai stanno stato stasera sto su subito te telefono tempo ti
    tra tu tutto tutti tua tuo un una uno va vai vado venire viene vengo vedere
    visto vita voglio vuole vorrei voi ieri domani mattina sera notte messaggio
    scuola università pranzo cena parlare scrivere hai bisogno paura felice forte
    chiusa chiuso aperta aperto porta armadio pacchi perde perso sconfitta
    """
    private static let english = """
    a about after again all also am an and another any are as ask at away back be
    because been before being best better big book both but buy by call called can
    cannot car case chat city close closed come coming could day days did do does
    doing done don't down each easy else even ever every fact family feel few find
    first fix food for found friend friends from get give go going good got great
    had happy has have he hello help her here him his home hope how i if in into
    is isn't it it's just keep know last late later leave left let life like little
    live long look lot love made make many may me mean message might more morning
    most mother much must my name need never new next nice night no not nothing now
    of off ok on once one only open or other our out over people phone place please
    possible probably put question read really right said same say school see send
    she should since small so some someone something soon sorry start stay still
    stop sure take talk tell text than thank thanks that the their them then there
    these they thing think this those through time to today together tomorrow too
    try two under until up us use very wait want was way we well were what when
    where which while who why will wish with without work world would write wrong
    yes yesterday yet you your you're lose lost afraid strong door package
    """
    private static let commonTypos = [
        "teh": "the", "thsi": "this", "thier": "their", "dont": "don't",
        "youre": "you're", "woudl": "would", "helo": "hello", "becuase": "because",
        "ciaoo": "ciao", "perche": "perché", "graziee": "grazie",
        "qunado": "quando", "qaundo": "quando", "buongirono": "buongiorno"
    ]

    private let vocabulary: SpellVocabulary
    private var protectedWords: Set<String>
    private var explicit: [String: String]
    private var learned: [String: String] = [:]
    private var personal: LocalLanguageModel.Snapshot
    private var validSystemWords: Set<String>
    let mode: KeyboardPreferences.LanguageMode
    var dominant: BilingualLanguageState.Language = .italian

    static let fallback = SpellVocabulary(
        italian: italian.split(whereSeparator: { $0.isWhitespace }).map { (String($0), 4.8) },
        english: english.split(whereSeparator: { $0.isWhitespace }).map { (String($0), 4.8) }
    )

    init(personal: LocalLanguageModel.Snapshot, mode: KeyboardPreferences.LanguageMode,
         lexicon: [(String, String)] = [], validSystemWords: Set<String> = [],
         vocabulary: SpellVocabulary = CorrectionIndex.fallback) {
        self.personal = personal
        self.mode = mode
        self.validSystemWords = validSystemWords
        self.vocabulary = vocabulary
        protectedWords = Set(personal.confirmedWords.keys)
        explicit = Self.commonTypos.filter { vocabulary.frequency($0.value, mode: mode) > 0 }
        for (input, output) in lexicon {
            if !input.isEmpty, !output.isEmpty {
                protectedWords.insert(output.lowercased())
                if input.lowercased() != output.lowercased() { explicit[input.lowercased()] = output }
            }
        }
        for (key, count) in personal.corrections.sorted(by: { $0.value > $1.value }) {
            let pair = key.components(separatedBy: "\u{1F}")
            if pair.count == 2, count > 0, learned[pair[0]] == nil { learned[pair[0]] = pair[1] }
        }
    }

    static func deletions(_ word: String) -> Set<String> {
        let chars = Array(word)
        guard chars.count <= 32 else { return [] }
        var values: Set<String> = [word]
        for index in chars.indices {
            var copy = chars
            copy.remove(at: index)
            values.insert(String(copy))
        }
        return values
    }

    func keeps(_ word: String) -> Bool {
        let lower = word.lowercased()
        return vocabulary.frequency(lower, mode: mode) > 0 || protects(lower) || validSystemWords.contains(lower)
    }

    func protects(_ word: String) -> Bool { protectedWords.contains(word.lowercased()) }
    func dictionaryFrequency(of word: String) -> Double { vocabulary.frequency(word, mode: mode) }

    func intentionalReplacement(for source: String) -> String? {
        let lower = source.lowercased()
        guard !protects(lower) else { return nil }
        return (learned[lower] ?? explicit[lower]).map { TextContext.matchCase($0, source: source) }
    }

    func correction(for source: String, previous: String?, systemGuesses: [String] = []) -> String? {
        let lower = source.lowercased()
        guard (3...24).contains(source.count), !source.contains(where: { $0.isNumber }),
              !protects(lower) else { return nil }
        if let intentional = intentionalReplacement(for: source) { return intentional }
        if Self.commonTypos[lower] != nil && explicit[lower] == nil && mode != .automatic { return nil }
        let previousIT = previous.map { vocabulary.frequency($0, mode: .italian) } ?? 0
        let previousEN = previous.map { vocabulary.frequency($0, mode: .english) } ?? 0
        let italianContext = mode == .italian || (mode == .automatic && previousIT - previousEN >= 0.8)
        let effectiveMode: KeyboardPreferences.LanguageMode = italianContext ? .italian : mode
        let sourceFrequency = vocabulary.frequency(lower, mode: effectiveMode)
        let validSource = sourceFrequency > 0 || validSystemWords.contains(lower)
        if sourceFrequency == 0 && validSystemWords.contains(lower) { return nil }
        // English words and common exact words are stable. Rare Italian fragments
        // may expand to a much more frequent word in Italian context (far -> fare).
        if validSource && !italianContext && sourceFrequency >= 4.2 { return nil }
        var candidates = vocabulary.candidates(for: lower, mode: effectiveMode).map { $0.word }
        for word in systemGuesses.prefix(8) where !candidates.contains(word.lowercased()) {
            candidates.append(word.lowercased())
        }
        let ranked: [(String, Double)] = candidates.compactMap { word in
            let distance = Self.editDistance(lower, word)
            guard word != lower, distance <= (lower.count >= 6 ? 2 : 1) else { return nil }
            let frequency = vocabulary.frequency(word, mode: effectiveMode)
            guard frequency >= 3.5 else { return nil }
            let isCompletion = word.hasPrefix(lower) && word.count == lower.count + 1
            let missingFirst = word.hasSuffix(lower) && word.count == lower.count + 1
            let cost = distance > 1 ? 1.6 : (isCompletion ? 0.35 : (missingFirst ? 0.45 : 0.95))
            let score = frequency - cost
                + min(0.6, log1p(Double(personal.frequency(of: word))) * 0.1)
                + min(1.0, log1p(Double(personal.contextFrequency(word, previous: previous))) * 0.3)
            if validSource {
                let gain = frequency - sourceFrequency
                guard gain >= (italianContext && isCompletion ? 0.45 : 2.0) else { return nil }
            }
            return (word, score)
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1 && best.1 - ranked[1].1 < 0.4 { return nil }
        return TextContext.matchCase(best.0, source: source)
    }

    mutating func markValid(_ word: String) {
        validSystemWords.insert(word.lowercased())
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 2, max(a.count, b.count) <= 40 else { return 99 }
        var previous = Array(0...b.count)
        var beforePrevious = previous
        for i in a.indices {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1,
                                 previous[j] + (a[i] == b[j] ? 0 : 1))
                if i > 0 && j > 0 && a[i] == b[j - 1] && a[i - 1] == b[j] {
                    row[j + 1] = min(row[j + 1], beforePrevious[j - 1] + 1)
                }
            }
            beforePrevious = previous
            previous = row
        }
        return previous[b.count]
    }
}

